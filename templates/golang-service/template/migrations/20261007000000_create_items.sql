-- First migration, as an example: replace or extend it with your service's
-- schema. Files apply once each, in file-name order, and are never edited
-- after they've been applied anywhere; change the schema with a new file.
--
-- Released separately from the code (see README.md), so keep changes
-- additive first: a column the running version doesn't know about is
-- harmless, a column it still reads is not.
CREATE TABLE items (
  id         bigserial   PRIMARY KEY,
  name       text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
