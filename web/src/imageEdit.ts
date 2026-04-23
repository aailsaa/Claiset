type CropArea = { x: number; y: number; width: number; height: number }

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error('Failed to load image'))
    img.crossOrigin = 'anonymous'
    img.src = src
  })
}

function degToRad(deg: number) {
  return (deg * Math.PI) / 180
}

function rotateSize(width: number, height: number, rotationRad: number) {
  const sin = Math.abs(Math.sin(rotationRad))
  const cos = Math.abs(Math.cos(rotationRad))
  return {
    width: width * cos + height * sin,
    height: width * sin + height * cos,
  }
}

/**
 * Crops and rotates an image dataUrl. Returns a PNG dataUrl.
 * `crop` is in pixels in the image's rendered coordinate space from react-easy-crop.
 */
export async function cropRotateToPngDataUrl(opts: {
  imageSrc: string
  crop: CropArea
  rotationDeg: number
}): Promise<string> {
  const image = await loadImage(opts.imageSrc)
  const rotation = degToRad(opts.rotationDeg || 0)

  // Draw the rotated image into a canvas sized to the rotated bounding box.
  // This matches the coordinate system used by react-easy-crop's croppedAreaPixels.
  const rot = rotateSize(image.width, image.height, rotation)
  const canvas = document.createElement('canvas')
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas unavailable')
  canvas.width = Math.round(rot.width)
  canvas.height = Math.round(rot.height)

  ctx.translate(canvas.width / 2, canvas.height / 2)
  ctx.rotate(rotation)
  ctx.drawImage(image, -image.width / 2, -image.height / 2)

  const cropX = Math.max(0, Math.round(opts.crop.x))
  const cropY = Math.max(0, Math.round(opts.crop.y))
  const cropW = Math.max(1, Math.round(opts.crop.width))
  const cropH = Math.max(1, Math.round(opts.crop.height))

  const imageData = ctx.getImageData(cropX, cropY, cropW, cropH)
  const out = document.createElement('canvas')
  const outCtx = out.getContext('2d')
  if (!outCtx) throw new Error('Canvas unavailable')
  out.width = cropW
  out.height = cropH
  outCtx.putImageData(imageData, 0, 0)

  return out.toDataURL('image/png')
}

