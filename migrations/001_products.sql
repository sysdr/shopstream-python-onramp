CREATE TABLE products (
    id     BIGSERIAL PRIMARY KEY,
    sku    TEXT NOT NULL UNIQUE,
    name   TEXT NOT NULL,
    price  NUMERIC(8, 2) NOT NULL CHECK (price > 0),
    stock  INTEGER NOT NULL CHECK (stock >= 0)
);

INSERT INTO products (sku, name, price, stock) VALUES
    ('SKU-1001', 'Trail running shoes', 89.00, 25),
    ('SKU-1002', 'Merino socks', 14.50, 120),
    ('SKU-1003', 'Rain jacket', 129.99, 12),
    ('SKU-1004', 'Water bottle', 19.99, 60),
    ('SKU-1005', 'Head torch', 34.00, 40);
