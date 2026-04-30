declare module 'heic2any' {
  export type Heic2AnyOptions = {
    blob: Blob
    toType: string
    quality?: number
  }

  export default function heic2any(opts: Heic2AnyOptions): Promise<Blob | Blob[]>
}

