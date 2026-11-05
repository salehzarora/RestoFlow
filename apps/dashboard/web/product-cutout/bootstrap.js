// Tiny Dashboard bridge. No model/runtime/worker loads until explicit processing.
(() => {
  const base = new URL('./bridge.mjs', document.currentScript.src);
  let module;
  let pendingOwner;
  let cancelledOwner;
  window.bizbotProductCutout = {
    async process(bytes, mimeType, progress, owner) {
      if (pendingOwner) throw new Error('Another product image is being processed');
      pendingOwner = owner;
      cancelledOwner = undefined;
      try {
      module ??= await import(base.href);
      if (cancelledOwner === owner) throw new Error('Cancelled');
      return await module.process(bytes, mimeType, progress, owner);
      } finally { pendingOwner = undefined; }
    },
    cancel(owner) { cancelledOwner = owner; module?.cancel(owner); },
  };
})();
