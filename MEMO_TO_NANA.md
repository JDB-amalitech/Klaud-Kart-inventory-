# Memo to Nana Adjei

**From:** Joseph Botchway · **Date:** 27 November 2026 · **Re:** Overselling, the Monday report, low stock and the stock trail

**The short version:** all four things you asked for are built and tested on your existing database, with no new servers or tools. Neither of the two fixes you were offered would have worked.

## What you now have

1. **No more overselling.** When two customers reach for the last unit at the same moment, exactly one gets it. The other is told "Out of stock" straight away. I tested this 25 times in a row and in a simulated flash sale of 400 buyers for 50 units: exactly 50 sold, every time, in under four seconds.
2. **The Monday report runs in about 1.5 seconds instead of 40 minutes.** For every customer it shows total spend, number of orders, spend for each of the last 12 months, the running total Adwoa keeps by hand, and the top 100. The old report asked the same question hundreds of thousands of times. The new one reads the orders once.
3. **Low stock at a glance.** A list of every category (Electronics → Phones → Phone Accessories → Cases) showing how many products are low or out, counting everything beneath it. It takes under a second.
4. **A stock trail an auditor can follow.** Every sale, restock, return and correction is recorded with who did it and, for sales, which order. Even a stock figure typed in by hand is caught and recorded.

## On the two suggestions you were given

- **Triggers would not have stopped overselling.** Two orders arriving together are each handled separately, and neither can see the other until it is finished, so both still believe the last unit is free. Triggers are useful, though: I used one to make sure no stock change goes unrecorded.
- **A bigger server would not have fixed the report.** The report was slow because of how it asked its questions, not because of the machine. A server twice as fast would still have taken over an hour.

## What I found in the data

- **14 products were already oversold.** Stock for another 144 does not match its own history.
- **Orders were recorded under 15 spellings of 5 statuses.** A report counting "completed" orders was seeing only 1 in 5 of them.
- **535 customers had two accounts**, which split their spending and pushed 3 of them out of your top 100.
- **About 1.5 million cedis of sales pointed at customers or orders that did not exist**, so reports simply left that money out.

All of this is now fixed or set aside for review. Nothing was deleted, and the database now refuses these mistakes.

## One improvement beyond what you asked

Stock now leaves the shelf when an order is **placed**, not when it ships. That is what stops overselling. It also means a cancelled order must put its stock back, so I added a cancel button that does exactly that and records the return. Without it, your stock would slowly read lower than you really have.

## What I recommend next

1. **Count the 144 products** whose stock and history disagree. Only a physical count can settle them.
2. **Send all sales and cancellations through the new tools**, and tell staff that hand edits to stock are now recorded under their name.
3. **Review the 1,895 orders** whose totals don't match their items. The list is ready.

## What I can't personally stand behind

- **The flash sale was simulated** on a laptop, not tested on your live server with real customers.
- **The 144 mismatched stock counts:** I don't know which figure is right until they are counted.
- **210 orders belong to customer numbers that don't exist.** They look like real sales, but someone needs to say whose they are.
- **418 duplicated order lines:** I can't tell whether these customers were undercharged or the stock was recorded twice. New sales can't have this problem, because each one is now tied to its order.
