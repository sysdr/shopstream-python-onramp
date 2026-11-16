CREATE TABLE orders (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products (id),
    qty         INTEGER NOT NULL CHECK (qty > 0),
    customer    TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX orders_product_idx ON orders (product_id);
