(() => {
  "use strict";

  // ── 1. Spoof hardware concurrency (3 cores → 4, very common value) ──
  Object.defineProperty(navigator, "hardwareConcurrency", {
    get: () => 4,
    configurable: true,
    enumerable: true,
  });

  // ── 2. Spoof device memory (2 GB → 8 GB, most common value) ──
  Object.defineProperty(navigator, "deviceMemory", {
    get: () => 8,
    configurable: true,
    enumerable: true,
  });

  // ── 3. Spoof WebGL renderer/vendor if SwiftShader is detected ──
  // SwiftShader (software renderer) is very identifiable at 4.62%.
  // Spoof to a common Intel Mesa renderer seen on Linux desktops.
  const UNMASKED_VENDOR_WEBGL = 0x9245;
  const UNMASKED_RENDERER_WEBGL = 0x9246;
  const SPOOFED_VENDOR = "Google Inc. (Intel)";
  const SPOOFED_RENDERER =
    "ANGLE (Intel, Mesa Intel(R) UHD Graphics 630 (CFL GT2), OpenGL ES 3.2)";

  function patchWebGL(proto) {
    const origGetParameter = proto.getParameter;
    proto.getParameter = function (param) {
      const value = origGetParameter.call(this, param);
      if (
        param === UNMASKED_RENDERER_WEBGL &&
        typeof value === "string" &&
        value.includes("SwiftShader")
      ) {
        return SPOOFED_RENDERER;
      }
      if (param === UNMASKED_VENDOR_WEBGL && typeof value === "string") {
        const renderer = origGetParameter.call(this, UNMASKED_RENDERER_WEBGL);
        if (typeof renderer === "string" && renderer.includes("SwiftShader")) {
          return SPOOFED_VENDOR;
        }
      }
      return value;
    };
  }

  if (typeof WebGLRenderingContext !== "undefined") {
    patchWebGL(WebGLRenderingContext.prototype);
  }
  if (typeof WebGL2RenderingContext !== "undefined") {
    patchWebGL(WebGL2RenderingContext.prototype);
  }

  // ── 4. Normalize navigator.plugins (remove Brave's randomized fake entries) ──
  // Brave's "Standard" fingerprint protection injects random plugin names like
  // "8mbsWyhQ" which makes the plugin list 0.00% unique. Standard Chrome returns
  // exactly these 5 PDF-related plugins.
  try {
    const standardNames = [
      ["PDF Viewer", "Portable Document Format", "internal-pdf-viewer"],
      ["Chrome PDF Viewer", "Portable Document Format", "internal-pdf-viewer"],
      [
        "Chromium PDF Viewer",
        "Portable Document Format",
        "internal-pdf-viewer",
      ],
      [
        "Microsoft Edge PDF Viewer",
        "Portable Document Format",
        "internal-pdf-viewer",
      ],
      [
        "WebKit built-in PDF",
        "Portable Document Format",
        "internal-pdf-viewer",
      ],
    ];

    const makeMimeType = (desc) => {
      const mt = Object.create(MimeType.prototype);
      Object.defineProperties(mt, {
        type: { get: () => "application/pdf", enumerable: true },
        description: { get: () => desc, enumerable: true },
        suffixes: { get: () => "pdf", enumerable: true },
        enabledPlugin: { get: () => null, enumerable: true },
      });
      return mt;
    };

    const makePlugin = (name, desc, filename) => {
      const mime = makeMimeType(desc);
      const plugin = Object.create(Plugin.prototype);
      Object.defineProperties(plugin, {
        name: { get: () => name, enumerable: true },
        description: { get: () => desc, enumerable: true },
        filename: { get: () => filename, enumerable: true },
        length: { get: () => 1, enumerable: true },
        0: { get: () => mime, enumerable: true },
      });
      plugin.item = (i) => (i === 0 ? mime : null);
      plugin.namedItem = (n) => (n === "application/pdf" ? mime : null);
      plugin[Symbol.iterator] = function* () {
        yield mime;
      };
      return plugin;
    };

    const plugins = standardNames.map(([n, d, f]) => makePlugin(n, d, f));

    Object.defineProperty(navigator, "plugins", {
      get: () => {
        const arr = Object.create(PluginArray.prototype);
        plugins.forEach((p, i) => {
          arr[i] = p;
        });
        Object.defineProperty(arr, "length", {
          get: () => plugins.length,
          enumerable: true,
        });
        arr.item = (i) => plugins[i] || null;
        arr.namedItem = (name) => plugins.find((p) => p.name === name) || null;
        arr.refresh = () => {};
        arr[Symbol.iterator] = function* () {
          for (const p of plugins) yield p;
        };
        return arr;
      },
      configurable: true,
      enumerable: true,
    });

    // Also normalize mimeTypes to match standard plugins
    const allMimes = [makeMimeType("Portable Document Format")];
    Object.defineProperty(navigator, "mimeTypes", {
      get: () => {
        const arr = Object.create(MimeTypeArray.prototype);
        allMimes.forEach((m, i) => {
          arr[i] = m;
        });
        Object.defineProperty(arr, "length", {
          get: () => allMimes.length,
          enumerable: true,
        });
        arr.item = (i) => allMimes[i] || null;
        arr.namedItem = (name) => allMimes.find((m) => m.type === name) || null;
        arr[Symbol.iterator] = function* () {
          for (const m of allMimes) yield m;
        };
        return arr;
      },
      configurable: true,
      enumerable: true,
    });
  } catch (e) {
    // Plugin/MimeType override failed — not critical
  }

  // ── 5. Canvas fingerprint noise ──
  // Add subtle deterministic noise to canvas readback to prevent unique fingerprinting.
  // This changes the canvas hash on each page load, preventing cross-site tracking.
  const origToDataURL = HTMLCanvasElement.prototype.toDataURL;
  HTMLCanvasElement.prototype.toDataURL = function (...args) {
    try {
      const ctx = this.getContext("2d");
      if (ctx && this.width > 0 && this.height > 0) {
        const w = Math.min(this.width, 32);
        const h = Math.min(this.height, 32);
        const imageData = ctx.getImageData(0, 0, w, h);
        const d = imageData.data;
        // XOR the least significant bit of a few R-channel pixels with random noise
        for (let i = 0; i < d.length && i < 128; i += 4) {
          d[i] ^= Math.random() > 0.5 ? 1 : 0;
        }
        ctx.putImageData(imageData, 0, 0);
      }
    } catch (e) {
      // WebGL canvas, cross-origin, or tainted — skip
    }
    return origToDataURL.apply(this, args);
  };

  const origToBlob = HTMLCanvasElement.prototype.toBlob;
  HTMLCanvasElement.prototype.toBlob = function (callback, ...args) {
    try {
      const ctx = this.getContext("2d");
      if (ctx && this.width > 0 && this.height > 0) {
        const w = Math.min(this.width, 32);
        const h = Math.min(this.height, 32);
        const imageData = ctx.getImageData(0, 0, w, h);
        const d = imageData.data;
        for (let i = 0; i < d.length && i < 128; i += 4) {
          d[i] ^= Math.random() > 0.5 ? 1 : 0;
        }
        ctx.putImageData(imageData, 0, 0);
      }
    } catch (e) {}
    return origToBlob.call(this, callback, ...args);
  };

  // ── 6. Block Battery API (containers always show charging=true, level=1) ──
  // Remove the battery API to avoid exposing VM/container characteristics
  if (navigator.getBattery) {
    Object.defineProperty(navigator, "getBattery", {
      get: () => undefined,
      configurable: true,
      enumerable: false,
    });
  }
})();
