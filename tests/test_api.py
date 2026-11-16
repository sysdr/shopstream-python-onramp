import uuid


def sku():
    return f"SKU-{uuid.uuid4().int % 900000 + 100000}"


def test_list_products(client):
    r = client.get("/products")
    assert r.status_code == 200
    assert [p["sku"] for p in r.json()][:2] == ["SKU-1001", "SKU-1002"]


def test_create_and_get(client):
    r = client.post("/products", json={"sku": sku(), "name": "Gaiters", "price": "24.00", "stock": 8})
    assert r.status_code == 201
    assert client.get(f"/products/{r.json()['id']}").json()["name"] == "Gaiters"


def test_validation_and_errors(client):
    assert client.post("/products", json={"sku": "bad", "name": "x", "price": "-5", "stock": 1}).status_code == 422
    assert client.post("/products", json={"sku": "SKU-1001", "name": "dup", "price": "1.00", "stock": 1}).status_code == 409
    assert client.get("/products/999999").status_code == 404


def test_search_treats_input_as_data(client):
    assert [p["name"] for p in client.get("/products/search", params={"q": "jacket"}).json()] == ["Rain jacket"]
    assert client.get("/products/search", params={"q": "x' OR '1'='1"}).json() == []


def test_migrations_are_recorded_once(test_database):
    from app import migrate
    assert migrate.migrate(test_database) == []  # already applied when the app started
