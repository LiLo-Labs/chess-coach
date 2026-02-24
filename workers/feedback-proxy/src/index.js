/**
 * Chess Coach Feedback Proxy
 *
 * Receives feedback from the iOS app and creates GitHub Issues.
 * The GitHub PAT is stored as a Cloudflare secret, never in the app.
 *
 * POST /feedback
 *   Body: { screen, category, message, appVersion?, osVersion?, device? }
 *   Returns: { success: true, issueUrl: "..." }
 */

export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: corsHeaders(),
      });
    }

    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const url = new URL(request.url);
    if (url.pathname !== "/feedback") {
      return jsonResponse({ error: "Not found" }, 404);
    }

    // Simple API key check (optional but recommended)
    const apiKey = request.headers.get("X-API-Key");
    if (env.API_KEY && apiKey !== env.API_KEY) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    try {
      const body = await request.json();
      const { screen, category, message, appVersion, osVersion, device } = body;

      if (!message || !category) {
        return jsonResponse({ error: "Missing required fields: message, category" }, 400);
      }

      // Build the GitHub Issue
      const title = `[${capitalize(category)}] ${screen || "App"}: ${message.slice(0, 60)}`;
      const issueBody = [
        `**Screen:** ${screen || "Unknown"}`,
        `**Category:** ${category}`,
        `**App Version:** ${appVersion || "unknown"}`,
        `**iOS Version:** ${osVersion || "unknown"}`,
        `**Device:** ${device || "unknown"}`,
        "",
        "---",
        "",
        message,
      ].join("\n");

      const labels = ["user-feedback"];
      if (["bug", "feature", "general"].includes(category)) {
        labels.push(category);
      }

      // Create the issue via GitHub API
      const repo = env.GITHUB_REPO || "MALathon/chess-coach";
      const ghResponse = await fetch(`https://api.github.com/repos/${repo}/issues`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.GITHUB_TOKEN}`,
          "Content-Type": "application/json",
          Accept: "application/vnd.github+json",
          "User-Agent": "chess-coach-feedback-worker",
        },
        body: JSON.stringify({ title, body: issueBody, labels }),
      });

      if (!ghResponse.ok) {
        const errText = await ghResponse.text();
        console.error(`GitHub API error ${ghResponse.status}: ${errText}`);
        return jsonResponse(
          { error: "Failed to create issue", status: ghResponse.status },
          502
        );
      }

      const issue = await ghResponse.json();
      return jsonResponse({
        success: true,
        issueUrl: issue.html_url,
        issueNumber: issue.number,
      });
    } catch (err) {
      console.error("Worker error:", err);
      return jsonResponse({ error: "Internal server error" }, 500);
    }
  },
};

function capitalize(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-API-Key",
  };
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(),
    },
  });
}
