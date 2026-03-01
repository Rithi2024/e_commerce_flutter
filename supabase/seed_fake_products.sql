-- Seed script: 200 fake products + variant stock rows
-- Run in Supabase SQL Editor after schema.sql

-- Optional cleanup (uncomment if you want to remove this seed set first):
-- delete from public.products where name like 'Demo %';

with numbered as (
  select
    gs as product_no,
    md5('marketflow-product-' || gs::text) as h
  from generate_series(1, 200) as gs
),
seed_products as (
  select
    product_no,
    format(
      '%s-%s-%s-%s-%s',
      substr(h, 1, 8),
      substr(h, 9, 4),
      substr(h, 13, 4),
      substr(h, 17, 4),
      substr(h, 21, 12)
    )::uuid as product_id,
    (array[
      'Clothing',
      'Shoes',
      'Accessories',
      'Electronics',
      'Beauty',
      'Home',
      'Sports',
      'Lifestyle'
    ])[1 + ((product_no - 1) % 8)] as category,
    (array[
      'Classic',
      'Urban',
      'Essential',
      'Premium',
      'Modern',
      'Sport',
      'Cozy',
      'Vintage'
    ])[1 + ((product_no - 1) % 8)] as style_word,
    (array[
      'T-Shirt',
      'Hoodie',
      'Sneakers',
      'Backpack',
      'Watch',
      'Headphones',
      'Jacket',
      'Jeans',
      'Dress',
      'Sunglasses'
    ])[1 + ((product_no - 1) % 10)] as product_word
  from numbered
)
insert into public.products (
  id,
  name,
  price,
  image_url,
  description,
  category,
  created_at
)
select
  sp.product_id,
  format('Demo %s %s %s', sp.style_word, sp.product_word, lpad(sp.product_no::text, 3, '0')),
  round((9 + ((sp.product_no * 137) % 9000) / 100.0)::numeric, 2),
  format('https://picsum.photos/seed/marketflow-%s/640/640', sp.product_no),
  format(
    'Seeded demo product %s in %s category for development and QA.',
    lpad(sp.product_no::text, 3, '0'),
    sp.category
  ),
  sp.category,
  now() - make_interval(days => ((sp.product_no - 1) % 45))
from seed_products sp
on conflict (id) do update
set
  name = excluded.name,
  price = excluded.price,
  image_url = excluded.image_url,
  description = excluded.description,
  category = excluded.category;

with numbered as (
  select
    gs as product_no,
    md5('marketflow-product-' || gs::text) as h
  from generate_series(1, 200) as gs
),
seed_products as (
  select
    product_no,
    format(
      '%s-%s-%s-%s-%s',
      substr(h, 1, 8),
      substr(h, 9, 4),
      substr(h, 13, 4),
      substr(h, 17, 4),
      substr(h, 21, 12)
    )::uuid as product_id
  from numbered
)
insert into public.product_variant_stocks (
  product_id,
  size,
  color,
  stock
)
select
  sp.product_id,
  s.size,
  c.color,
  6 + ((sp.product_no * 3 + s.size_idx * 5 + c.color_idx * 7) % 25)
from seed_products sp
cross join (
  values
    ('S', 1),
    ('M', 2),
    ('L', 3),
    ('XL', 4)
) as s(size, size_idx)
cross join (
  values
    ('Black', 1),
    ('White', 2),
    ('Blue', 3),
    ('Red', 4)
) as c(color, color_idx)
on conflict (product_id, size, color) do nothing;

select count(*) as seeded_demo_products
from public.products
where name like 'Demo %';
