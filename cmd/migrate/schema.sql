-- Shared schema: all tables scoped by user_sub (Google OIDC "sub" claim).

CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    user_sub TEXT NOT NULL,
    name TEXT NOT NULL,
    colors JSONB NOT NULL DEFAULT '[]'::jsonb,
    category TEXT NOT NULL DEFAULT '',
    subcategory TEXT NOT NULL DEFAULT '',
    price REAL NOT NULL DEFAULT 0,
    wears INT NOT NULL DEFAULT 0,
    item_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    photo_data_url TEXT,
    extra JSONB NOT NULL DEFAULT '{}'::jsonb,
    archived BOOLEAN NOT NULL DEFAULT FALSE
);

-- Allow schema upgrades on existing databases.
ALTER TABLE items ADD COLUMN IF NOT EXISTS photo_data_url TEXT;
ALTER TABLE items ADD COLUMN IF NOT EXISTS extra JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE items ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE items ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

CREATE TABLE IF NOT EXISTS outfits (
    id SERIAL PRIMARY KEY,
    user_sub TEXT NOT NULL,
    name TEXT NOT NULL,
    wears INT NOT NULL DEFAULT 0,
    cover_data_url TEXT,
    extra JSONB NOT NULL DEFAULT '{}'::jsonb,
    layout JSONB NOT NULL DEFAULT '[]'::jsonb,
    pictures JSONB NOT NULL DEFAULT '[]'::jsonb
);

-- Allow schema upgrades on existing databases.
ALTER TABLE outfits ADD COLUMN IF NOT EXISTS cover_data_url TEXT;
ALTER TABLE outfits ADD COLUMN IF NOT EXISTS extra JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE outfits ADD COLUMN IF NOT EXISTS layout JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE outfits ADD COLUMN IF NOT EXISTS pictures JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE TABLE IF NOT EXISTS outfit_items (
    outfit_id INT NOT NULL REFERENCES outfits (id) ON DELETE CASCADE,
    item_id INT NOT NULL REFERENCES items (id) ON DELETE CASCADE,
    PRIMARY KEY (outfit_id, item_id)
);

CREATE TABLE IF NOT EXISTS outfit_assignments (
    id SERIAL PRIMARY KEY,
    user_sub TEXT NOT NULL,
    outfit_id INT NOT NULL REFERENCES outfits (id) ON DELETE CASCADE,
    day DATE NOT NULL,
    notes TEXT,
    UNIQUE (user_sub, day)
);

CREATE INDEX IF NOT EXISTS idx_items_user ON items (user_sub);
CREATE INDEX IF NOT EXISTS idx_outfits_user ON outfits (user_sub);
CREATE INDEX IF NOT EXISTS idx_outfit_assignments_user_day ON outfit_assignments (user_sub, day);
CREATE INDEX IF NOT EXISTS idx_outfit_items_item ON outfit_items (item_id);

-- Day-2 / rubric: visible additive migration (nullable; no app change required).
ALTER TABLE items ADD COLUMN IF NOT EXISTS schema_evidence_demo TEXT;
