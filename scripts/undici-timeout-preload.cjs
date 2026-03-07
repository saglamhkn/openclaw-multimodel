// Monkey-patch undici to extend HTTP timeouts for slow Ollama responses
// OpenClaw disables streaming for Ollama, so the full response must complete
// before the HTTP request returns. This extends the timeout to 30 minutes.
try {
  const undici = require("undici");

  const OPTS = {
    headersTimeout: 30 * 60 * 1000, // 30 minutes
    bodyTimeout: 0,                 // Disable body timeout
  };

  const realSet = undici.setGlobalDispatcher.bind(undici);
  function enforce() {
    realSet(new undici.EnvHttpProxyAgent(OPTS));
  }
  enforce();
  undici.setGlobalDispatcher = function () {
    enforce();
  };
} catch {
  // undici not available as standalone module — Node 22+ bundles it internally
  // Try loading from node:internal or skip gracefully
  try {
    const { setGlobalDispatcher, EnvHttpProxyAgent } = require("node:undici");
    const OPTS = {
      headersTimeout: 30 * 60 * 1000,
      bodyTimeout: 0,
    };
    setGlobalDispatcher(new EnvHttpProxyAgent(OPTS));
  } catch {
    // Could not patch timeouts — will use defaults
  }
}
