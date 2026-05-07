import { removeBackground } from '@imgly/background-removal'

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onerror = () => reject(new Error('Failed to read image'))
    r.onload = () => resolve(String(r.result))
    r.readAsDataURL(blob)
  })
}

export type BgModel = 'isnet' | 'isnet_fp16' | 'isnet_quint8'
export type BgPostprocessTuning = 'balanced' | 'cleaner' | 'preserveEdges' | 'aggressive'

export async function fileToDataUrl(file: Blob): Promise<string> {
  return blobToDataUrl(file)
}

async function resizeToMaxDimension(file: File, maxDim: number): Promise<File> {
  const bmp = await createImageBitmap(file)
  const scale = Math.min(1, maxDim / Math.max(bmp.width, bmp.height))
  const w = Math.max(1, Math.round(bmp.width * scale))
  const h = Math.max(1, Math.round(bmp.height * scale))
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  if (!ctx) return file
  canvas.width = w
  canvas.height = h
  ctx.drawImage(bmp, 0, 0, w, h)
  const blob = await new Promise<Blob>((resolve) => canvas.toBlob((b) => resolve(b as Blob), 'image/png'))
  return new File([blob], file.name.replace(/\.[^/.]+$/, '') + '.png', { type: 'image/png' })
}

async function dataUrlToImageData(dataUrl: string): Promise<{ data: ImageData; width: number; height: number }> {
  const img = new Image()
  img.crossOrigin = 'anonymous'
  const loaded = new Promise<void>((resolve, reject) => {
    img.onload = () => resolve()
    img.onerror = () => reject(new Error('Failed to load image'))
  })
  img.src = dataUrl
  await loaded
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas unavailable')
  canvas.width = img.naturalWidth || img.width
  canvas.height = img.naturalHeight || img.height
  ctx.drawImage(img, 0, 0)
  return { data: ctx.getImageData(0, 0, canvas.width, canvas.height), width: canvas.width, height: canvas.height }
}

function maskKeepLargestComponent(mask: Uint8ClampedArray, width: number, height: number, alphaThreshold: number) {
  const n = width * height
  const seen = new Uint8Array(n)
  const bin = new Uint8Array(n)
  for (let i = 0; i < n; i++) bin[i] = mask[i] > alphaThreshold ? 1 : 0

  let bestCount = 0
  let bestSeed = -1
  const qx: number[] = []
  const qy: number[] = []

  function bfs(seed: number) {
    qx.length = 0
    qy.length = 0
    const sx = seed % width
    const sy = (seed / width) | 0
    qx.push(sx)
    qy.push(sy)
    seen[seed] = 1
    let count = 0
    while (qx.length) {
      const x = qx.pop() as number
      const y = qy.pop() as number
      count++
      const neighbors = [
        [x - 1, y],
        [x + 1, y],
        [x, y - 1],
        [x, y + 1],
      ]
      for (const [nx, ny] of neighbors) {
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
        const idx = ny * width + nx
        if (seen[idx]) continue
        if (!bin[idx]) continue
        seen[idx] = 1
        qx.push(nx)
        qy.push(ny)
      }
    }
    return count
  }

  for (let i = 0; i < n; i++) {
    if (seen[i] || !bin[i]) continue
    const count = bfs(i)
    if (count > bestCount) {
      bestCount = count
      bestSeed = i
    }
  }

  // Clear all
  mask.fill(0)
  if (bestSeed < 0) return

  // Re-run BFS to mark best component (write 255).
  const stack: number[] = [bestSeed]
  const seen2 = new Uint8Array(n)
  seen2[bestSeed] = 1
  while (stack.length) {
    const idx = stack.pop() as number
    mask[idx] = 255
    const x = idx % width
    const y = (idx / width) | 0
    const neighbors = [
      [x - 1, y],
      [x + 1, y],
      [x, y - 1],
      [x, y + 1],
    ]
    for (const [nx, ny] of neighbors) {
      if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue
      const j = ny * width + nx
      if (seen2[j]) continue
      if (!bin[j]) continue
      seen2[j] = 1
      stack.push(j)
    }
  }
}

function fillHoles(binMask: Uint8ClampedArray, width: number, height: number) {
  // binMask is 0/255. Fill holes inside the foreground region.
  const n = width * height
  const visited = new Uint8Array(n)
  const q: number[] = []

  function pushIf(i: number) {
    if (visited[i]) return
    if (binMask[i] !== 0) return // only traverse background
    visited[i] = 1
    q.push(i)
  }

  // seed with border background pixels
  for (let x = 0; x < width; x++) {
    pushIf(x)
    pushIf((height - 1) * width + x)
  }
  for (let y = 0; y < height; y++) {
    pushIf(y * width)
    pushIf(y * width + (width - 1))
  }

  while (q.length) {
    const i = q.pop() as number
    const x = i % width
    const y = (i / width) | 0
    if (x > 0) pushIf(i - 1)
    if (x + 1 < width) pushIf(i + 1)
    if (y > 0) pushIf(i - width)
    if (y + 1 < height) pushIf(i + width)
  }

  // any remaining background pixels (not connected to border) are holes -> fill
  for (let i = 0; i < n; i++) {
    if (binMask[i] === 0 && !visited[i]) binMask[i] = 255
  }
}

function dilate(bin: Uint8ClampedArray, width: number, height: number, radius: number) {
  const out = new Uint8ClampedArray(bin.length)
  const r = Math.max(1, radius)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let best = 0
      const y0 = Math.max(0, y - r)
      const y1 = Math.min(height - 1, y + r)
      const x0 = Math.max(0, x - r)
      const x1 = Math.min(width - 1, x + r)
      for (let yy = y0; yy <= y1; yy++) {
        const row = yy * width
        for (let xx = x0; xx <= x1; xx++) {
          const v = bin[row + xx]
          if (v > best) best = v
        }
      }
      out[y * width + x] = best
    }
  }
  return out
}

function erode(bin: Uint8ClampedArray, width: number, height: number, radius: number) {
  const out = new Uint8ClampedArray(bin.length)
  const r = Math.max(1, radius)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let best = 255
      const y0 = Math.max(0, y - r)
      const y1 = Math.min(height - 1, y + r)
      const x0 = Math.max(0, x - r)
      const x1 = Math.min(width - 1, x + r)
      for (let yy = y0; yy <= y1; yy++) {
        const row = yy * width
        for (let xx = x0; xx <= x1; xx++) {
          const v = bin[row + xx]
          if (v < best) best = v
        }
      }
      out[y * width + x] = best
    }
  }
  return out
}

function blurAlpha(alpha: Uint8ClampedArray, width: number, height: number, radius: number) {
  const r = Math.max(1, radius)
  const tmp = new Uint8ClampedArray(alpha.length)
  // horizontal
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0
      let count = 0
      const x0 = Math.max(0, x - r)
      const x1 = Math.min(width - 1, x + r)
      for (let xx = x0; xx <= x1; xx++) {
        sum += alpha[y * width + xx]
        count++
      }
      tmp[y * width + x] = (sum / count) | 0
    }
  }
  const out = new Uint8ClampedArray(alpha.length)
  // vertical
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0
      let count = 0
      const y0 = Math.max(0, y - r)
      const y1 = Math.min(height - 1, y + r)
      for (let yy = y0; yy <= y1; yy++) {
        sum += tmp[yy * width + x]
        count++
      }
      out[y * width + x] = (sum / count) | 0
    }
  }
  return out
}

function composeFromMask(original: ImageData, mask: Uint8ClampedArray): ImageData {
  const { width, height } = original
  const out = new ImageData(width, height)
  const o = original.data
  for (let i = 0; i < width * height; i++) {
    const idx = i * 4
    out.data[idx + 0] = o[idx + 0]
    out.data[idx + 1] = o[idx + 1]
    out.data[idx + 2] = o[idx + 2]
    out.data[idx + 3] = mask[i]
  }
  return out
}

/**
 * Removes the background and returns a PNG data URL (with transparency).
 * Falls back to the original image data URL if background removal fails.
 */
export async function removeBackgroundToDataUrl(
  file: File,
  opts?: {
    model?: BgModel
    device?: 'cpu' | 'gpu'
    tuning?: BgPostprocessTuning
  },
): Promise<{
  dataUrl: string
  removed: boolean
  modelUsed: BgModel
}> {
  // Resize for more stable matting and faster processing.
  const resized = await resizeToMaxDimension(file, 1600)
  const originalDataUrl = await blobToDataUrl(resized)
  const modelUsed: BgModel = opts?.model ?? 'isnet'
  try {
    async function run(device: 'cpu' | 'gpu' | undefined) {
      return await removeBackground(resized, {
        model: modelUsed,
        device,
        output: { format: 'image/png' },
      })
    }

    // Prefer GPU, but gracefully fall back to CPU if WebGPU isn't available.
    const preferred = opts?.device ?? 'gpu'
    let outBlob: Blob
    try {
      outBlob = await run(preferred)
    } catch {
      if (preferred === 'gpu') {
        outBlob = await run('cpu')
      } else {
        throw new Error('background removal failed')
      }
    }

    const dataUrl = await blobToDataUrl(outBlob)
    // Post-process mask:
    // 1) keep the largest connected component (the garment)
    // 2) close small gaps + fill small holes
    // 3) feather edges for a clean cutout
    try {
      const [orig, rem] = await Promise.all([dataUrlToImageData(originalDataUrl), dataUrlToImageData(dataUrl)])
      if (orig.width === rem.width && orig.height === rem.height) {
        const w = orig.width
        const h = orig.height
        const alpha = new Uint8ClampedArray(w * h)
        for (let i = 0; i < w * h; i++) alpha[i] = rem.data.data[i * 4 + 3]

        // Default to a stronger cleanup profile so initial results remove more background.
        const tuning: BgPostprocessTuning = opts?.tuning ?? 'cleaner'
        const params =
          tuning === 'aggressive'
            ? { keepThreshold: 36, closeRadius: 2, expand: 0, erodeAfter: 3, blur: 1 }
            : tuning === 'cleaner'
              ? { keepThreshold: 28, closeRadius: 2, expand: 0, erodeAfter: 2, blur: 1 }
              : tuning === 'preserveEdges'
                ? { keepThreshold: 6, closeRadius: 3, expand: 2, erodeAfter: 0, blur: 1 }
                : { keepThreshold: 10, closeRadius: 3, expand: 1, erodeAfter: 0, blur: 1 }

        // Keep the garment and discard stray background islands.
        maskKeepLargestComponent(alpha, w, h, params.keepThreshold)

        // Closing fills holes and reconnects stripes that get cut.
        const closed = erode(dilate(alpha, w, h, params.closeRadius), w, h, params.closeRadius)
        fillHoles(closed, w, h)

        // Optional expansion to protect light edges; optional erosion to cut leftover background.
        let tuned = closed
        if (params.expand > 0) tuned = dilate(tuned, w, h, params.expand)
        if (params.erodeAfter > 0) tuned = erode(tuned, w, h, params.erodeAfter)

        const feathered = blurAlpha(tuned, w, h, params.blur)

        const protectedImg = composeFromMask(orig.data, feathered)
        const canvas = document.createElement('canvas')
        const ctx = canvas.getContext('2d')
        if (ctx) {
          canvas.width = orig.width
          canvas.height = orig.height
          ctx.putImageData(protectedImg, 0, 0)
          const protectedUrl = canvas.toDataURL('image/png')
          return { dataUrl: protectedUrl, removed: true, modelUsed }
        }
      }
    } catch {
      // ignore and return unprotected result
    }
    return { dataUrl, removed: true, modelUsed }
  } catch {
    return { dataUrl: originalDataUrl, removed: false, modelUsed }
  }
}

