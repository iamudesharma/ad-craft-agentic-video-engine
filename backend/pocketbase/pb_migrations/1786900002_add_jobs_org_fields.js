/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  collection.fields.add(
    new RelationField({
      name: "org_id",
      collectionId: app.findCollectionByNameOrId("organizations").id,
      maxSelect: 1,
    }),
  );
  collection.fields.add(
    new RelationField({
      name: "created_by",
      collectionId: "_pb_users_auth_",
      maxSelect: 1,
    }),
  );
  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  const orgField = collection.fields.findByName("org_id");
  const createdByField = collection.fields.findByName("created_by");
  if (orgField) collection.fields.remove(orgField);
  if (createdByField) collection.fields.remove(createdByField);
  return app.save(collection);
});