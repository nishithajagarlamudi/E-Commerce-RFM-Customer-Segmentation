set global local_infile=1;

-- Create Database if not exist
create database if not exists olist_rfm;
use olist_rfm;

-- Create Table customers if not exist
CREATE TABLE IF NOT EXISTS customers (
    customer_id              VARCHAR(50) PRIMARY KEY,
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(100),
    customer_state           VARCHAR(10)
);

-- Create Table orders if not exist
CREATE TABLE IF NOT EXISTS orders (
    order_id                      VARCHAR(50) PRIMARY KEY,
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(30),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME,
    order_delivered_carrier_date  DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

-- Create Table order_payments if not exist
CREATE TABLE IF NOT EXISTS order_payments (
    order_id             VARCHAR(50),
    payment_sequential   INT,
    payment_type         VARCHAR(30),
    payment_installments INT,
    payment_value        DECIMAL(10,2)
);

-- Create Table order_items if not exist
CREATE TABLE IF NOT EXISTS order_items (
    order_id            VARCHAR(50),
    order_item_id       INT,
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date DATETIME,
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2)
);

-- Import customers
LOAD DATA LOCAL INFILE 'C:/Users/Naveen Krishna/Downloads/archive (12)/olist_customers_dataset.csv' 
INTO TABLE customers
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Import orders 
LOAD DATA LOCAL INFILE 'C:/Users/Naveen Krishna/Downloads/archive (12)/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, customer_id, order_status, @op, @oa, @odc, @odd, @oed)
SET
  order_purchase_timestamp      = NULLIF(@op,  ''),
  order_approved_at             = NULLIF(@oa,  ''),
  order_delivered_carrier_date  = NULLIF(@odc, ''),
  order_delivered_customer_date = NULLIF(@odd, ''),
  order_estimated_delivery_date = NULLIF(@oed, '');

-- Import order payments
LOAD DATA LOCAL INFILE 'C:/Users/Naveen Krishna/Downloads/archive (12)/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- Import order items
LOAD DATA LOCAL INFILE 'C:/Users/Naveen Krishna/Downloads/archive (12)/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(order_id, order_item_id, product_id, seller_id, @sld, price, freight_value)
SET shipping_limit_date = NULLIF(@sld, '');


-- Verify row counts
SELECT 'customers'     AS tbl, COUNT(*) AS n_rows FROM customers    UNION ALL
SELECT 'orders'        AS tbl, COUNT(*) AS n_rows FROM orders        UNION ALL
SELECT 'order_payments'AS tbl, COUNT(*) AS n_rows FROM order_payments UNION ALL
SELECT 'order_items'   AS tbl, COUNT(*) AS n_rows FROM order_items;


-- Raw RFM values
create or replace view raw_rfm as 
select 
c.customer_unique_id as customer_id,
max(order_purchase_timestamp) as last_order,
datediff(  (select max(order_purchase_timestamp) from orders), max(order_purchase_timestamp)) as recency_days,
count(distinct o.order_id) as frequency,
sum(round(op.payment_value,2)) as monetary
from customers c join orders o on c.customer_id=o.customer_id
join order_payments op on o.order_id=op.order_id
where order_status='delivered'
group by customer_unique_id;

select * from raw_rfm order by monetary desc limit 10;


-- RFM scores
create or replace view rfm_score as
select customer_id,last_order,recency_days,frequency,monetary,
case when recency_days<=30 then 5
when recency_days<=90 then 4
when recency_days<=180 then 3
when recency_days<=360 then 2
else 1
end as r_score,
case when frequency>=5 then 5
when frequency=4 then 4
when frequency=3 then 3
when frequency=2 then 2
else 1
end as f_score,
case when monetary>=1000 then 5
when monetary>=500 then 4
when monetary>=200 then 3
when monetary>=100 then 2
else 1
end as m_score
from raw_rfm;

select * from rfm_score order by r_score desc,f_score desc limit 10;


-- RFM segments
create or replace view rfm_segment as
select customer_id,
last_order,
recency_days,
frequency,
monetary,
r_score,
f_score,
m_score,
(r_score+f_score+m_score) as total_score,
case 
when r_score = 5 and f_score >= 4 and m_score >= 4  then 'Champion'
when r_score >= 4 and f_score >= 4                  THEN 'Loyal Customer'
when r_score = 5 and f_score = 1                    THEN 'New Customer'
when r_score >= 4 and f_score BETWEEN 2 AND 3       THEN 'Potential Loyal'
when r_score = 3 and f_score >= 3                   THEN 'Needs Attention'
when r_score BETWEEN 2 and 3 and f_score >= 2       THEN 'At Risk'
when r_score BETWEEN 2 and 3 and f_score = 1        THEN 'Hibernating'
when r_score = 1                                     THEN 'Lost'
else 'Others'
end AS segment
from rfm_score;

select * from rfm_segment order by total_score desc;


-- Segment summary
select segment,
count(customer_id) as total_customers,
round(avg(recency_days),1) as avg_recency_days,
round(avg(frequency),1) as avg_orders,
round(avg(monetary),1) as avg_spend,
round(sum(monetary),1) as total_revenue,
round( count(customer_id)*100.0 / (select count(*) from rfm_segment),1) as pct_customers
from rfm_segment
group by segment
order by total_revenue desc;


-- Top 10 Champions
select customer_id,
recency_days,
frequency,
monetary,
total_score
from rfm_segment
where segment="Champion"
order by monetary desc 
limit 10;

-- Top 10 At Risk
select customer_id,
recency_days,
frequency,
monetary,
total_score
from rfm_segment
where segment="At Risk"
order by monetary desc 
limit 10;

-- Revenue by segment 
select 
segment,
count(customer_id) as customers,
round(sum(monetary),2) as total_revenue,
round(avg(monetary),2) as avg_revenue,
round(sum(monetary)*100.0 / (select sum(monetary) from rfm_segment),2) as revenue_pct
from rfm_segment
group by segment
order by total_revenue desc;


-- Marketing action plan
select 
customer_id,
segment,
monetary,
recency_days,
case segment
when 'Champion' then 'Reward + Early access + Ask for review'
when 'Loyal Customer' then 'Upsell + Loyalty points + Referral ask'
when 'Potential Loyal' then 'Membership offer + Frequency nudge'
when 'New Customer' then 'Onboarding email + 2nd purchase discount'
when 'Needs Attention' then 'Send personalised recommendations'
when 'At Risk' then 'Win-back email + Special offer'
when 'Hibernating' then 'Reactivation campaign + Discount'
when 'Lost' then 'Last chance email or suppress'
else 'Monitor'
end as recommended_action
from rfm_segment
order by segment,monetary desc;


create table rfm_final as
select * from rfm_segment;

select 
(select count(*) from rfm_final) as total_customers,
round( (select count(*) from rfm_final where segment = 'At Risk') * 100.0 /
(select count(*) from rfm_final), 1) as at_risk_pct,
round( (select sum(monetary) from rfm_final where segment = 'At Risk') * 100.0 /
(select sum(monetary) from rfm_final), 1) as at_risk_revenue_pct;