// PocketBase background jobs (cron hooks)
//
// - jobs-timeout-watchdog: marks jobs stuck in pending/running longer than
//   30 minutes as failed. Runs even when the Python backend is down.
// - jobs-media-sweep: deletes media output of failed jobs older than 7 days.
//
// NOTE: cron callbacks run in a separate scope (module-level consts are not
// visible there), so everything is defined inside each callback.
//
// NOTE: the jobs collection carries explicit created_at/updated_at autodate
// fields (PB 0.39 removed the system ones from the API). Timeout comparisons
// are done server-side via datetime literals in PB's native format
// ("YYYY-MM-DD HH:mm:ss.SSSZ"), which avoids Goja Date conversion quirks.

cronAdd("jobs-timeout-watchdog", "*/5 * * * *", () => {
  const pbDateTime = (d) => {
    const pad = (n) => String(n).padStart(2, "0");
    const pad3 = (n) => String(n).padStart(3, "0");
    return (
      d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()) +
      " " + pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds()) +
      "." + pad3(d.getUTCMilliseconds()) + "Z"
    );
  };
  const timeoutSeconds = 30 * 60;
  const cutoff = pbDateTime(new Date(Date.now() - timeoutSeconds * 1000));
  const stale = $app.findRecordsByFilter(
    "jobs",
    '(status = "pending" || status = "running") && updated_at < "' + cutoff + '"',
  );
  for (const record of stale) {
    record.set("status", "failed");
    record.set("error", "Job timed out — stuck for more than " + timeoutSeconds / 60 + " minutes");
    $app.save(record);
    console.log("watchdog: marked stale job " + record.id + " as failed");
  }
});

cronAdd("jobs-media-sweep", "0 3 * * *", () => {
  const pbDateTime = (d) => {
    const pad = (n) => String(n).padStart(2, "0");
    const pad3 = (n) => String(n).padStart(3, "0");
    return (
      d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()) +
      " " + pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()) + ":" + pad(d.getUTCSeconds()) +
      "." + pad3(d.getUTCMilliseconds()) + "Z"
    );
  };
  const retentionSeconds = 7 * 24 * 60 * 60;
  const cutoff = pbDateTime(new Date(Date.now() - retentionSeconds * 1000));
  const oldFailed = $app.findRecordsByFilter(
    "jobs",
    'status = "failed" && updated_at < "' + cutoff + '"',
  );
  for (const record of oldFailed) {
    try {
      const path = require("path");
      const fs = require("fs");
      // media lives at <repo>/backend/media/<job_id>, pb_data is at <repo>/backend/pocketbase/pb_data
      const mediaDir = path.join($app.getDataDir(), "..", "..", "media", record.id);
      fs.rmSync(mediaDir, { recursive: true, force: true });
      console.log("media sweep: removed " + mediaDir);
    } catch (e) {
      console.error("media sweep failed for job " + record.id + ": " + e.message);
    }
  }
});
