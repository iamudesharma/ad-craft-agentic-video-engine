/// <reference path="../pb_data/types.d.ts" />

// PB 0.39 removed the system `created`/`updated` fields from the records API
// (they are neither serialized nor sortable/queryable), so the jobs collection
// carries explicit autodate timestamps maintained by PocketBase itself.

migrate((app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  collection.fields.add(new AutodateField({ name: "created_at", onCreate: true }));
  collection.fields.add(new AutodateField({ name: "updated_at", onCreate: true, onUpdate: true }));
  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  collection.fields.remove("created_at");
  collection.fields.remove("updated_at");
  return app.save(collection);
});
