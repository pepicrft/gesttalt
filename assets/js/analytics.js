(() => {
  const host = document.querySelector("meta[name='smolanalytics-host']")?.content?.replace(/\/$/, "")
  const writeKey = document.querySelector("meta[name='smolanalytics-write-key']")?.content

  if (!host || !writeKey) return

  const sdk = document.createElement("script")
  sdk.src = `${host}/sdk.js`
  sdk.async = true
  sdk.addEventListener("load", () => {
    window.smolanalytics?.init(writeKey, {host, anonymous: true})
  })
  sdk.addEventListener("error", () => {
    console.warn("smolanalytics: the browser client could not be loaded")
  })
  document.head.appendChild(sdk)
})()
