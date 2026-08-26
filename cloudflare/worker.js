export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true, service: "gha-indie-worker-edge" });
    }
    return fetch(request);
  },
};

