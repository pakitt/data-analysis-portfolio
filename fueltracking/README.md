# Hybrid vs Diesel Commuting in Munich (2002–2018)
## Cost, efficiency, and travel-time analysis using longitudinal real-world data

## Executive Summary
- Analyzed **1,350+ real-world commute records** collected over 16 years in Munich
- Compared fuel costs, efficiency, and travel time across **diesel and two hybrid vehicles**
- Found that **petrol hybrids reduced fuel costs by ~15% on average**, particularly in urban traffic
- Identified optimal commuting routes and time-of-day patterns affecting both cost and duration

The full interactive analysis is available as a Power BI report:
👉 [Fuel consumption tracking (Power BI)](https://github.com/pakitt/data-analysis-portfolio/blob/main/fueltracking/Fuel%20consumption%20tracking.pbix)

---

## Questions This Analysis Answers
- Do petrol hybrid vehicles reduce commuting fuel costs compared to diesel in city traffic?
- How does **time of day** affect commute duration?
- Which **route** consistently minimizes time and fuel consumption?
- How do **day of the week** and **traffic patterns** influence results?
- Is there a measurable efficiency improvement between **Prius Gen3 and Gen4**?
- Do **seasonal factors** (winter vs summer tyres, temperature) impact fuel consumption?

---

## Data & Methodology

### Data Collection
- **Period:** 2002–2018  
- **Commute distance:** ~18 km daily  
- **Records:** 1,350+ individual commute and refuelling entries  
- **Source:** Manually tracked Excel logs consolidated into Power BI

### Data Features
- Commute time (to/from work)
- Fuel prices
- Fuel consumption (vehicle MFD-reported)
- Ambient temperature at destination
- Route selection
- Average speed

### Notes & Exclusions
- MFD fuel consumption readings are ~5% optimistic across all vehicles  
- Accuracy correction and **Total Cost of Ownership (TCO)** analysis were intentionally excluded from this report to keep scope focused

---

## Vehicles Analyzed

### VW Polo 1.4 TDI (2002–2009)
<img src="https://github.com/user-attachments/assets/20d2445e-a2ee-4eee-95c2-37f2840be681" width="300">

### Toyota Prius – 3rd Generation (2009–2016)
<img src="https://github.com/user-attachments/assets/c977bc9c-34e9-4699-bb1e-e1a931615951" width="300">

### Toyota Prius – 4th Generation (2016–2018)
<img src="https://github.com/user-attachments/assets/5567d8f6-9188-4768-9029-36d6885752db" width="300">

These vehicles represent a progression from traditional diesel to successive generations of full hybrid technology under comparable commuting conditions.

---

## How to Explore the Analysis
- Open the **Power BI Desktop (.pbix)** file linked above
- Use filters to explore:
  - Vehicle type
  - Route
  - Time of day
  - Temperature ranges
- Review supporting charts exported in the `assets/` folder
