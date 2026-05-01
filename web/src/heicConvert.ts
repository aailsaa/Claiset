import { heicTo } from 'heic-to'

function isHeicFile(file: File): boolean {
  const n = (file.name || '').toLowerCase()
  return (
    file.type === 'image/heic' ||
    file.type === 'image/heif' ||
    n.endsWith('.heic') ||
    n.endsWith('.heif')
  )
}

function formatErr(e: unknown): string {
  if (e instanceof Error) return e.message || e.name || 'Error'
  if (typeof e === 'string') return e
  if (e && typeof e === 'object') {
    const m = (e as { message?: unknown }).message
    if (typeof m === 'string' && m) return m
    try {
      return JSON.stringify(e)
    } catch {
      return String(e)
    }
  }
  return String(e)
}

function jpegFileFrom(blob: Blob, baseName: string, source: File): File {
  if (!blob || blob.size === 0) throw new Error('empty conversion result')
  return new File([blob], `${baseName}.jpg`, { type: 'image/jpeg', lastModified: source.lastModified })
}

function pngFileFrom(blob: Blob, baseName: string, source: File): File {
  if (!blob || blob.size === 0) throw new Error('empty conversion result')
  return new File([blob], `${baseName}.png`, { type: 'image/png', lastModified: source.lastModified })
}

/**
 * Safari (and some WebKit builds) decode HEIC in the platform image pipeline.
 */
async function heicToJpegViaCreateImageBitmap(file: File, buf: ArrayBuffer, baseName: string): Promise<File | null> {
  const candidates: Blob[] = [
    file,
    new Blob([buf], { type: 'image/heic' }),
    new Blob([buf], { type: 'image/heif' }),
    new Blob([buf], { type: 'application/octet-stream' }),
  ]

  for (const blob of candidates) {
    try {
      const bmp = await createImageBitmap(blob)
      const w = bmp.width
      const h = bmp.height
      if (!w || !h) {
        bmp.close?.()
        continue
      }
      const canvas = document.createElement('canvas')
      canvas.width = w
      canvas.height = h
      const ctx = canvas.getContext('2d')
      if (!ctx) {
        bmp.close?.()
        continue
      }
      ctx.drawImage(bmp, 0, 0)
      bmp.close?.()
      const outBlob = await new Promise<Blob | null>((resolve) =>
        canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.92),
      )
      if (!outBlob || outBlob.size === 0) continue
      return jpegFileFrom(outBlob, baseName, file)
    } catch {
      // try next candidate
    }
  }
  return null
}

async function bmpToJpegFile(bmp: ImageBitmap, baseName: string, source: File): Promise<File | null> {
  const w = bmp.width
  const h = bmp.height
  if (!w || !h) {
    bmp.close?.()
    return null
  }
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = h
  const ctx = canvas.getContext('2d')
  if (!ctx) {
    bmp.close?.()
    return null
  }
  ctx.drawImage(bmp, 0, 0)
  bmp.close?.()
  const outBlob = await new Promise<Blob | null>((resolve) =>
    canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.92),
  )
  if (!outBlob || outBlob.size === 0) return null
  return jpegFileFrom(outBlob, baseName, source)
}

/**
 * HEIC/HEIF → JPEG or PNG:
 * 1) Native decode (Safari/macOS preview path)
 * 2) heic-to (recent libheif WASM — avoids outdated heic2any “ERR_LIBHEIF format not supported” on newer iPhones)
 */
export async function ensureBrowserReadableImage(file: File): Promise<File> {
  if (!isHeicFile(file)) return file

  const baseName = ((file.name || 'photo').replace(/\.(heic|heif)$/i, '') || 'photo').replace(/[^\w\- .]+/g, '_')
  const buf = await file.arrayBuffer()

  const native = await heicToJpegViaCreateImageBitmap(file, buf, baseName)
  if (native) return native

  const blobSources: Blob[] = [
    file,
    new Blob([buf], { type: file.type || 'image/heic' }),
    new Blob([buf], { type: 'image/heic' }),
    new Blob([buf], { type: 'image/heif' }),
  ]

  const errors: string[] = []

  for (const blobIn of blobSources) {
    for (const q of [0.92, 0.75, 0.5] as const) {
      try {
        const blob = await heicTo({ blob: blobIn, type: 'image/jpeg', quality: q })
        return jpegFileFrom(blob, baseName, file)
      } catch (e) {
        errors.push(formatErr(e))
      }
    }
    try {
      const blob = await heicTo({ blob: blobIn, type: 'image/png' })
      return pngFileFrom(blob, baseName, file)
    } catch (e) {
      errors.push(formatErr(e))
    }
  }

  for (const blobIn of blobSources) {
    try {
      const bmp = await heicTo({ blob: blobIn, type: 'bitmap' })
      const f = await bmpToJpegFile(bmp, baseName, file)
      if (f) return f
    } catch (e) {
      errors.push(formatErr(e))
    }
  }

  const distinct = [...new Set(errors)].filter(Boolean).slice(0, 5)
  const hint = distinct.length ? distinct.join('; ') : 'decoder could not read this HEIC variant'

  throw new Error(
    `Could not convert this HEIC (${hint}). If this persists, export as JPEG from Photos/Preview or set iPhone Camera → Formats → “Most Compatible”.`,
  )
}
