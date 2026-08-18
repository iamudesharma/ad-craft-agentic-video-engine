/// <reference path="../pb_data/types.d.ts" />

migrate((app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  collection.fields.add(
    new RelationField({
      name: "favorited_by",
      collectionId: "_pb_users_auth_",
      maxSelect: 100,
      cascadeDelete: false,
    }),
  );
  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("jobs");
  const field = collection.fields.findByName("favorited_by");
  if (field) collection.fields.remove(field);
  return app.save(collection);
});
