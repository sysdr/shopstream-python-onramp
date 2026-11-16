# Day 1: Your first API in 20 minutes

Every backend starts the same way: a URL that returns data. Today you build ShopStream's first one, a product catalog API, with FastAPI. In about 60 lines you get JSON responses, input validation that rejects bad data before your code runs, clear error codes, and interactive documentation you didn't have to write.

## What you build

A FastAPI app with four endpoints, running in Docker on port 8201:

| Method and path | What it does | Errors |
|---|---|---|
| `GET /health` | Says the process is up | — |
| `GET /products?limit=&offset=` | Lists products, 20 per page by default | 422 for a bad limit |
| `GET /products/{id}` | One product | 404 if it doesn't exist |
| `POST /products` | Creates a product | 422 for invalid data, 409 for a duplicate SKU |

The products live in a Python dictionary for now. That's deliberate: it lets you focus on HTTP and validation today, and it gives Day 2 a real problem to solve (restart the container and new products vanish).

## The model is the contract

```python
class ProductIn(BaseModel):
    sku: str = Field(pattern=r"^SKU-[0-9]{1,6}$")
    name: str = Field(min_length=1, max_length=120)
    price: Decimal = Field(gt=0, max_digits=8, decimal_places=2)
    stock: int = Field(ge=0)


@app.post("/products", response_model=Product, status_code=201)
def create_product(body: ProductIn):
    ...
```

FastAPI reads the type hint `body: ProductIn` and does three jobs with it: it parses the JSON, validates every field against the rules, and documents the shape at `/docs`. If any rule fails, the request is rejected with **422 Unprocessable Entity** and a list of every bad field — your function never runs.

Two details that matter later:

- **Price is a `Decimal`, not a `float`.** Money must be exact; Day 4 shows what floats do to prices.
- **Status codes carry meaning.** 201 means created, 404 means not found, 409 means it conflicts with something that exists, 422 means your input is wrong. Clients can act on the code without parsing the message.

## What we measured

Running the demo on Docker Desktop:

- **First request:** `GET /products?limit=3` answered with 200 in **18 ms**, including the wait for start-up.
- **200 more requests**, one at a time: **p50 2.2 ms, p99 4.0 ms**.
- **A bad product** — `{"sku": "shoe", "name": "", "price": "-5"}` — came back as 422 naming three problems at once: the SKU doesn't match `SKU-` plus digits, the name is empty, the price isn't greater than 0.
- **The same SKU twice:** the second attempt got **409** `SKU-1006 already exists`.

## Read it in the docs

Open **http://localhost:8201/docs**. FastAPI generated an interactive page from your code: every endpoint, every field and its rules, and a "Try it out" button. Send the bad product from there and you'll see the same 422.

## Try it

```bash
curl -s localhost:8201/products?limit=2
curl -s -X POST localhost:8201/products -H 'Content-Type: application/json' \
  -d '{"sku":"SKU-2001","name":"Gaiters","price":"24.00","stock":8}'
curl -s localhost:8201/products/999
```

## Say it in an interview

**Q: Why validate at the edge of the API?**
A: Invalid data is rejected before it reaches business logic or the database, with an error that tells the client exactly what to fix. One schema gives you validation, documentation and a contract with clients.

**Q: What's the difference between 400, 404, 409 and 422?**
A: 400 is a malformed request, 404 is a resource that doesn't exist, 409 conflicts with current state (a duplicate key), and 422 is well-formed JSON that breaks the rules of the schema.

**Q: Why not store prices as floats?**
A: Binary floats can't represent most decimal fractions exactly, so sums and rounding drift by cents. Use a decimal type or integer cents.

## Recap

- FastAPI + Pydantic: the model is the validation, the documentation and the contract.
- Measured: first request 18 ms; p50 2.2 ms, p99 4.0 ms; invalid input rejected with every bad field listed.
- Status codes: 201, 404, 409, 422 each tell the client something specific.
- The data is in memory, so it disappears on restart — Day 2 fixes that.

## Challenge (10 minutes)

Add `PATCH /products/{id}` that changes only the price and stock, validated with the same rules.

<details class="sdc-hint"><summary>Hint 1</summary>Make a `ProductUpdate` model where both fields are optional: `price: Decimal | None = Field(None, gt=0)`.</details>

<details class="sdc-hint"><summary>Hint 2</summary>Use `body.model_dump(exclude_unset=True)` to get only the fields the client sent.</details>

<details class="sdc-hint"><summary>Hint 3</summary>Return 404 for an unknown id, then `PRODUCTS[id] = PRODUCTS[id].model_copy(update=changes)`.</details>
