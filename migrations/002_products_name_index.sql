-- Searching by name is the most common query; an index on lower(name) serves exact, case-insensitive lookups.
CREATE INDEX products_lower_name_idx ON products (lower(name));
