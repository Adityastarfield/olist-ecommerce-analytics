# DAX Measures

All measures live in the `_Measures` table (a dummy table created with `_Measures = ROW("dummy", 1)`, used purely as an organizational home for measures rather than to store data).

## Core aggregates

```dax
Total Revenue = SUM(vw_fact_order_items[price])

Total Orders = DISTINCTCOUNT(vw_fact_order_items[order_id])

Total Customers = DISTINCTCOUNT(vw_fact_order_items[customer_unique_id])

Total Freight = SUM(vw_fact_order_items[freight_value])

Total Items Sold = COUNTROWS(vw_fact_order_items)

Total Payment Value = SUM(vw_fact_payments[payment_value])

AOV = DIVIDE([Total Revenue], [Total Orders])

Avg Item Price = AVERAGE(vw_fact_order_items[price])

Avg Review Score = AVERAGE(vw_fact_orders[review_score])
```

## Delivery performance

```dax
Avg Delivery Days =
CALCULATE(
    AVERAGEX(
        vw_fact_orders,
        DATEDIFF(
            vw_fact_orders[order_purchase_timestamp],
            vw_fact_orders[order_delivered_customer_date],
            DAY
        )
    ),
    TREATAS(
        VALUES(vw_fact_order_items[order_id]),
        vw_fact_orders[order_id]
    )
)

% Delayed Orders =
DIVIDE(
    CALCULATE(
        DISTINCTCOUNT(vw_fact_orders[order_id]),
        vw_fact_orders[order_delivered_customer_date] > vw_fact_orders[order_estimated_delivery_date]
    ),
    DISTINCTCOUNT(vw_fact_orders[order_id])
)

% Delayed Orders by Category =
VAR CategoryOrders =
    CALCULATETABLE(
        VALUES(vw_fact_order_items[order_id])
    )
VAR DelayedOrders =
    CALCULATE(
        DISTINCTCOUNT(vw_fact_orders[order_id]),
        TREATAS(
            CategoryOrders,
            vw_fact_orders[order_id]
        ),
        vw_fact_orders[order_delivered_customer_date]
            > vw_fact_orders[order_estimated_delivery_date]
    )
VAR TotalCategoryOrders =
    CALCULATE(
        DISTINCTCOUNT(vw_fact_orders[order_id]),
        TREATAS(
            CategoryOrders,
            vw_fact_orders[order_id]
        )
    )
RETURN
    DIVIDE(DelayedOrders, TotalCategoryOrders)

Seller Delay Rank =
VAR CurrentOrders = MAX(vw_seller_delivery_performance[total_delivered_orders])
VAR CurrentDelay = MAX(vw_seller_delivery_performance[delay_percentage])
RETURN
IF(
    CurrentOrders > 10,
    RANKX(
        FILTER(
            ALL(vw_seller_delivery_performance),
            vw_seller_delivery_performance[total_delivered_orders] > 10
        ),
        CALCULATE(MAX(vw_seller_delivery_performance[delay_percentage])),
        CurrentDelay,
        DESC
    ),
    BLANK()
)
```

**Note:** `Seller Delay Rank` has no visual of its own — it's used as a filter condition (`Seller Delay Rank <= 15`) on the "worst-performing sellers" table on the Delivery & Operations page, to focus on sellers with a genuinely poor rank rather than showing every seller with 11+ orders.

## Data-sparsity handling

```dax
Insufficient Data Flag =
IF(
    ISBLANK([Total Orders]) || [Total Orders] < 500,
    "Insufficient order volume for this period.",
    ""
)

Overlay BG Color =
IF(
    ISBLANK([Total Orders]) || [Total Orders] < 500,
    "#FFFFFF",
    "#FFFFFF00"
)
```

Drives a conditionally-visible text overlay on charts affected by the very low order volume in late 2016 (the marketplace's early launch months), so the chart shows an explanation instead of an unexplained blank panel when a thin period is selected. The condition checks actual order volume rather than hardcoding the year 2016, so it generalizes to any other thin slice (e.g. a sparse month/state combination), not just that one specific case.

## Review score

```dax
Avg Review Score by Category =
CALCULATE(
    AVERAGE(vw_fact_orders[review_score]),
    TREATAS(
        VALUES(vw_fact_order_items[order_id]),
        vw_fact_orders[order_id]
    )
)

Orders by Delivery Status = DISTINCTCOUNT(vw_fact_orders[order_id])

Orders by Review Score = DISTINCTCOUNT(vw_fact_orders[order_id])
```

## Customer / RFM

```dax
% of Total Customers =
DIVIDE(
    [Total Customers],
    CALCULATE([Total Customers], ALL(vw_rfm_segments[customer_segment]))
)

% of Total Revenue =
DIVIDE(
    [Total Revenue],
    CALCULATE([Total Revenue], ALL(vw_rfm_segments[customer_segment]))
)

% One-Time Customers = 
VAR OneTimeCount = 
    CALCULATE(
        DISTINCTCOUNT(vw_rfm_segments[customer_unique_id]),
        vw_rfm_segments[customer_segment] = "One-Time Customers",
        ALL(vw_rfm_segments[customer_segment])
    )

VAR TotalCount = 
    CALCULATE(
        DISTINCTCOUNT(vw_rfm_segments[customer_unique_id]),
        ALL(vw_rfm_segments[customer_segment])
    )

RETURN
    DIVIDE(OneTimeCount, TotalCount)

% True One-Time Customers =
DIVIDE(
    CALCULATE(
        DISTINCTCOUNT(vw_rfm_segments[customer_unique_id]),
        vw_rfm_segments[frequency] = 1,
        ALL(vw_rfm_segments[customer_segment])
    ),
    CALCULATE(
        DISTINCTCOUNT(vw_rfm_segments[customer_unique_id]),
        ALL(vw_rfm_segments[customer_segment])
    )
)

% Revenue from True One-Time Customers =
DIVIDE(
    CALCULATE(
        SUM(vw_rfm_segments[monetary]),
        vw_rfm_segments[frequency] = 1,
        ALL(vw_rfm_segments[customer_segment])
    ),
    CALCULATE(
        SUM(vw_rfm_segments[monetary]),
        ALL(vw_rfm_segments[customer_segment])
    )
)
```

**Note:** these measures filter on frequency = 1 directly, not on customer_segment = "One-Time Customers". The RFM segmentation splits frequency-1 customers into two segments — "One-Time Customers" and "High-Value New Customers" — based on recency and spend, so the segment-based `% One-Time Customers` measure (81.46%) understates the true one-time-purchase rate. These two measures answer "what fraction of all customers/revenue comes from people who have only ordered once," regardless of which RFM segment they landed in.

## Time intelligence

```dax
Revenue PM = CALCULATE([Total Revenue], DATEADD(Dim_Date[Date], -1, MONTH))

MoM Growth % =
IF(
    MAX('Dim_Date'[YearMonthNum]) < 201702 || MAX('Dim_Date'[YearMonthNum]) = 201809,
    BLANK(),
    DIVIDE([Total Revenue] - [Revenue PM], [Revenue PM])
)
```

**Note:** `Revenue PM` has no visual of its own — it exists purely as a helper measure that `MoM Growth %` depends on. `MoM Growth %` self-suppresses for Nov 2016–Jan 2017 (near-zero revenue base makes the percentage swing meaningless) and Sep 2018 (a data cliff at the end of the dataset), using `Dim_Date[YearMonthNum]` (a calculated column: `YEAR([Date]) * 100 + MONTH([Date])`) rather than filtering the visual, so the underlying revenue bars still display correctly even in months where the growth-rate line is hidden.

## `Dim_Date`

```dax
Dim_Date =
ADDCOLUMNS(
    CALENDAR(DATE(2016,1,1), DATE(2018,12,31)),
    "Year", YEAR([Date]),
    "Month Number", MONTH([Date]),
    "Month Name", FORMAT([Date], "MMMM"),
    "Month Year", FORMAT([Date], "MMM YYYY"),
    "Quarter", "Q" & FORMAT([Date], "Q"),
    "Day", DAY([Date]),
    "Weekday", FORMAT([Date], "ddd")
)
```

Marked as an official Date Table (Modeling → Mark as Date Table) so `DATEADD` in `Revenue PM` works correctly. `YearMonthNum` is added afterward as a separate calculated column on the table (`YEAR(Dim_Date[Date]) * 100 + MONTH(Dim_Date[Date])`), not part of this table-generating expression.
