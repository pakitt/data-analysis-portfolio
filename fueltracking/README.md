# Hybrid vs Diesel Commuting in Munich (2002–2018)
## Cost, efficiency, and travel-time analysis using longitudinal real-world data

<p align="center">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/hero-dashboard.png" width="600" alt="Fuel consumption and commute analysis - Power BI dashboard">
</p>

## Project snapshot

**Context**  
Daily 18 km commute in Munich (2002–2018), switching from diesel to hybrid vehicles.

**Goal**  
Evaluate whether petrol hybrids reduced fuel costs and commute times versus diesel, and identify optimal commuting strategies.

**Tools**  
Excel (data collection), Power BI (data modeling & visualization)

**Data volume**  
1,350+ commute-level observations over 16 years

---

## Data collected

| Category            | Details |
|---------------------|--------|
| Commute metrics     | Time, route, average speed |
| Fuel data           | Price, consumption (MFD) |
| Environment         | Ambient temperature |
| Vehicle attributes  | Diesel vs Hybrid (Gen3/Gen4) |
| Scope exclusions     | MFD accuracy correction, Total Cost of Ownership (TCO) |

> Raw data was originally tracked across multiple Excel files and later consolidated, cleaned, and modeled in Power BI.

### Notes & Exclusions
- MFD fuel consumption readings are ~5% optimistic across all vehicles  
- Accuracy correction and **Total Cost of Ownership (TCO)** analysis were intentionally excluded from this report to keep scope focused

---

## Key questions & insights

### Did petrol hybrids reduce commute fuel costs compared to diesel?
<p align="left">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/fuel-cost-comparison.png" width="500" alt="Fuel cost comparison">
</p>

**Finding:**  
Petrol hybrids consistently reduced fuel cost per commute, even under dense urban stop-and-go traffic conditions and higher petrol prices.

---

### How does time of day affect commute duration?
<p align="left">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/commute_time_by_hour.png" width="500" alt="Commute time by hour">
</p>

**Finding:**  
Leaving home or the office has a significant impact on commute time, even during peak congestion hours. Small adjustments to morning departure time can deliver clear and measurable time savings.

---

### Which route performed best?
<p align="left">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/route_comparison.png" width="500" alt="Route comparison">
</p>

**Finding:**  
Alternative routes offered measurable trade-offs between time and fuel efficiency, enabling route optimization depending on traffic conditions.

---

### Did newer hybrid generations improve efficiency?
<p align="left">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/gen3_gen4_comparison.png" width="500" alt="Route comparison">
</p>

**Finding:**  
The 4th generation Prius delivered incremental fuel efficiency gains over the 3rd generation, though traffic patterns and increasing fuel cost remained the dominant factor in overall trip cost improvement.

---

### Do seasonal factors matter?
<p align="left">
  <img src="https://raw.githubusercontent.com/pakitt/data-analysis-portfolio/main/assets/temperature_consumption.png" width="500" alt="Temperature vs consumption comparison">
</p>

**Finding:**  
Winter conditions, usage of winter tyres, and seasonal traffic patterns increased consumption.

---

## Vehicles analyzed

| Vehicle | Period | Powertrain |
|-------|--------|------------|
| <img src="https://github.com/user-attachments/assets/20d2445e-a2ee-4eee-95c2-37f2840be681" width="150"> | 2002–2009 | Diesel (VW Polo 1.4 TDI) |
| <img src="https://github.com/user-attachments/assets/c977bc9c-34e9-4699-bb1e-e1a931615951" width="150"> | 2009–2016 | Petrol Hybrid (Toyota Prius – 3rd Generation) |
| <img src="https://github.com/user-attachments/assets/5567d8f6-9188-4768-9029-36d6885752db" width="150"> | 2016–2018 | Petrol Hybrid (Toyota Prius – 4th Generation)|

These vehicles represent a progression from traditional diesel to successive generations of full hybrid technology under comparable commuting conditions.

---

## Dashboard & analysis file

The complete interactive Power BI report is available here and includes route comparisons, time-of-day analysis, and vehicle efficiency breakdowns:  
👉 **[Fuel consumption & commute analysis (Power BI)](https://github.com/pakitt/data-analysis-portfolio/blob/main/fueltracking/Fuel%20consumption%20tracking.pbix)**

--- 

## Why this project matters

- Demonstrates analysis of a large, longitudinal real-world dataset (16 years, 1,350+ observations)
- Controls for external variables by analyzing the same commute, city, and user across vehicles
- Shows end-to-end analytical workflow: raw data consolidation → modeling → insight generation
- Focuses on practical, decision-oriented insights rather than hypothetical scenarios

---

## Skills demonstrated

- Long-term data consolidation, normalization, and modeling  
- Comparative and exploratory data analysis  
- Power BI dashboard design and analytical storytelling  
- Translating raw behavioral data into actionable insights
