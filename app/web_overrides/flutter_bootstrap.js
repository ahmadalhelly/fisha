{{flutter_js}}
{{flutter_build_config}}

// The hub's launcher page (http://<hub>:8080/app) sets window.FISHA_BASE to this site's URL and loads this file
// from here, so the app runs on the hub's http origin (local LAN API allowed) with its code and assets from here.
// No service worker: it cannot be registered across origins, and the browser cache is enough.
(function () {
  var base = window.FISHA_BASE;
  // CanvasKit is served from this site too (not gstatic), so only one host has to be reachable
  var config = { canvasKitBaseUrl: (base || '') + 'canvaskit/' };
  if (base) { config.entrypointBaseUrl = base; config.assetBase = base; }
  _flutter.loader.load({ config: config });
})();
