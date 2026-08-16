/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
  const collection = new Collection({
    type: "base",
    name: "jobs",
    fields: [
      { name: "user_prompt", type: "text", required: true },
      { name: "brand_guidelines", type: "text" },
      { name: "aspect_ratio", type: "text" },
      { name: "hitl_enabled", type: "bool" },
      { name: "status", type: "text", index: true },
      { name: "storyboard", type: "json" },
      { name: "final_video_path", type: "text" },
      { name: "error", type: "text" },
    ],
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  return app.delete(collection);
});
