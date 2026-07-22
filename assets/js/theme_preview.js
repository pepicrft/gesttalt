const clientStorageKey = "gesttalt:theme-preview-client-id"
const previewPathPattern = /^\/theme-previews\/[^/]+/

const previewClientId = () => {
  if (!previewPathPattern.test(window.location.pathname)) return null

  let clientId = window.sessionStorage.getItem(clientStorageKey)

  if (!clientId) {
    clientId = window.crypto.randomUUID()
    window.sessionStorage.setItem(clientStorageKey, clientId)
  }

  return clientId
}

const viewport = () => ({
  device_pixel_ratio: window.devicePixelRatio,
  height: window.innerHeight,
  width: window.innerWidth,
})

export const themePreviewConnectParams = () => {
  const clientId = previewClientId()

  return clientId ? {
    theme_preview_client_id: clientId,
    theme_preview_viewport: viewport(),
  } : {}
}

export const ThemePreview = {
  mounted() {
    this.captureStream = null
    this.captureVideo = null

    this.onClick = event => {
      const action = event.target.closest?.('[data-action="enable-screenshots"]')
      if (action && this.el.contains(action)) this.enableScreenshots(action)
    }

    this.onFrameMessage = event => {
      const frame = this.el.querySelector("#theme-preview-site")
      if (event.source !== frame?.contentWindow) return
      if (event.data?.type !== "gesttalt:theme-preview:navigate") return
      if (typeof event.data.path !== "string") return

      this.pushEvent("navigate-theme-preview", {path: event.data.path})
    }

    this.onPopState = () => {
      if (previewPathPattern.test(window.location.pathname)) {
        this.pushEvent("navigate-theme-preview", {path: window.location.pathname})
      }
    }

    this.onResize = () => {
      window.clearTimeout(this.resizeTimer)
      this.resizeTimer = window.setTimeout(() => {
        this.pushEvent("theme-preview-presence", {viewport: viewport()})
      }, 150)
    }

    this.el.addEventListener("click", this.onClick)
    window.addEventListener("message", this.onFrameMessage)
    window.addEventListener("popstate", this.onPopState)
    window.addEventListener("resize", this.onResize)

    this.handleEvent("theme-preview:navigated", ({path}) => {
      if (window.location.pathname !== path) window.history.pushState({}, "", path)
    })

    this.handleEvent("theme-preview:capture", ({request_id: requestId}) => {
      this.captureScreenshot(requestId)
    })

    this.handleEvent("theme-preview:stop-capture", () => this.stopScreenshots())
  },

  destroyed() {
    window.clearTimeout(this.resizeTimer)
    this.el.removeEventListener("click", this.onClick)
    window.removeEventListener("message", this.onFrameMessage)
    window.removeEventListener("popstate", this.onPopState)
    window.removeEventListener("resize", this.onResize)
    this.stopScreenshots()
  },

  reconnected() {
    this.pushEvent("theme-preview-presence", {viewport: viewport()})

    if (this.captureStream?.active) {
      this.pushEvent("theme-preview-screenshot-access", {enabled: true})
    }
  },

  async enableScreenshots(button) {
    if (this.captureStream?.active) return

    if (!navigator.mediaDevices?.getDisplayMedia) {
      button.textContent = "Screen capture unavailable"
      return
    }

    button.disabled = true
    button.textContent = "Choose this tab…"

    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({
        audio: false,
        preferCurrentTab: true,
        selfBrowserSurface: "include",
        surfaceSwitching: "exclude",
        systemAudio: "exclude",
        video: {
          displaySurface: "browser",
          frameRate: {ideal: 1, max: 5},
        },
      })

      const video = document.createElement("video")
      video.autoplay = true
      video.muted = true
      video.playsInline = true
      video.srcObject = stream
      await video.play()

      this.captureStream = stream
      this.captureVideo = video

      stream.getVideoTracks().forEach(track => {
        track.addEventListener("ended", () => this.stopScreenshots(true), {once: true})
      })

      this.pushEvent("theme-preview-screenshot-access", {enabled: true})
    } catch (_error) {
      button.disabled = false
      button.textContent = "Allow screenshots"
      this.pushEvent("theme-preview-screenshot-access", {enabled: false})
    }
  },

  stopScreenshots(notify = false) {
    const stream = this.captureStream
    this.captureStream = null
    this.captureVideo = null

    stream?.getTracks().forEach(track => track.stop())

    if (notify && this.el.isConnected) {
      this.pushEvent("theme-preview-screenshot-access", {enabled: false})
    }
  },

  async captureScreenshot(requestId) {
    const stream = this.captureStream
    const video = this.captureVideo

    if (!stream?.active || !video || video.readyState < HTMLMediaElement.HAVE_CURRENT_DATA) {
      this.pushEvent("theme-preview-screenshot-failed", {
        reason: "screenshot_permission_required",
        request_id: requestId,
      })
      return
    }

    try {
      const width = video.videoWidth
      const height = video.videoHeight
      const canvas = document.createElement("canvas")
      canvas.width = width
      canvas.height = height
      canvas.getContext("2d").drawImage(video, 0, 0, width, height)

      const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/png"))
      if (!blob) throw new Error("The browser did not produce an image")

      const screenshot = new File(
        [blob],
        `${requestId}--${width}x${height}.png`,
        {type: "image/png"},
      )

      this.upload("theme_preview_screenshot", [screenshot])
    } catch (_error) {
      this.pushEvent("theme-preview-screenshot-failed", {
        reason: stream.active ? "capture_failed" : "capture_stream_ended",
        request_id: requestId,
      })
    }
  },
}
