(() => {
  if (navigator.webdriver) return

  fetch("/analytics/pageview", {
    method: "POST",
    credentials: "omit",
    keepalive: true,
    headers: {"content-type": "application/json"},
    body: JSON.stringify({path: window.location.pathname}),
  }).catch(() => {})
})()
