/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
  const organizations = new Collection({
    type: "base",
    name: "organizations",
    fields: [
      { name: "name", type: "text", required: true },
      { name: "brand_name", type: "text" },
      { name: "tagline", type: "text" },
      { name: "tone_of_voice", type: "text" },
      { name: "colors", type: "json" },
      { name: "typography", type: "text" },
      { name: "visual_style", type: "text" },
      { name: "do_list", type: "json" },
      { name: "dont_list", type: "json" },
      { name: "target_audience", type: "text" },
      { name: "created_at", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated_at", type: "autodate", onCreate: true, onUpdate: true },
    ],
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
  });
  app.save(organizations);

  const members = new Collection({
    type: "base",
    name: "org_members",
    fields: [
      { name: "org_id", type: "relation", required: true, collectionId: organizations.id, maxSelect: 1 },
      { name: "user_id", type: "relation", required: true, collectionId: "_pb_users_auth_", maxSelect: 1 },
      { name: "role", type: "text", required: true, max: 20 },
      { name: "created_at", type: "autodate", onCreate: true, onUpdate: false },
      { name: "updated_at", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: [
      "CREATE UNIQUE INDEX idx_org_members_org_user ON org_members (org_id, user_id)",
    ],
    listRule: "",
    viewRule: "",
    createRule: null,
    updateRule: null,
    deleteRule: null,
  });
  app.save(members);
}, (app) => {
  app.delete(app.findCollectionByNameOrId("org_members"));
  app.delete(app.findCollectionByNameOrId("organizations"));
});