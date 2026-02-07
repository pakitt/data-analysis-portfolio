import pandas as pd

#Import raw data into a dataframe
file_path = "data/car-sales-data-raw.txt"

try:
    # Read all lines from file, skipping first 2 rows
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()[2:]  # Skip first 2 lines

    # Strip newline characters but keep the rest of the text exactly as-is
    lines = [line.rstrip("\n") for line in lines]

    # Create DataFrame with one column
    df = pd.DataFrame(lines, columns=["raw_data"])
    input_rows = len(df)      # dataframe right after reading the file

except FileNotFoundError:
    print(f"Error: File '{file_path}' not found.")
except Exception as e:
    print(f"An unexpected error occurred: {e}")

#Split raw_data into columns according to patterns
pattern = (
    r"^(?P<Customer>.*?)\s+Car:\s+"
    r"(?P<Car_Model>.*?)(?:\s+£)?"
    r"(?P<Sale>\d{1,3}(?:,\d{3})*)\s+"
    r"(?P<Location>[A-Za-z\s]+?)\s+"
    r"(?P<Payment_Type>Cash|Card)\s+"
    r"(?P<Card_Number>\d+)\s+"
    r"(?P<Transaction_Date>\d{2}/\d{2}/\d{4})$"
)

extracted = df["raw_data"].str.extract(pattern)
df = pd.concat([df, extracted], axis=1)

df["Sale"] = (
    df["Sale"]
    .str.replace(",", "", regex=False)
    .astype(int)
)

df["Transaction_Date"] = pd.to_datetime(
    df["Transaction_Date"],
    format="%d/%m/%Y"
)

df = df.drop(columns=["raw_data"])

#check that all rows are still there after import and manipulation of columns
output_rows = len(df)            # dataframe after extraction
assert input_rows == output_rows, (
    f"Row count mismatch: input={input_rows}, output={output_rows}"
)

#check that split into rows was valid and there are no NaN
failed_rows = df[df[["Customer", "Car_Model", "Sale",
                     "Location", "Card_Number", "Transaction_Date"]].isna().any(axis=1)]

if not failed_rows.empty:
    raise ValueError(
        f"{len(failed_rows)} rows failed parsing. Example:\n"
        f"{failed_rows['raw_data'].head(3).to_string(index=False)}"
    )

#create customerID for PII obfuscation
df["Customer_ID"] = (
    df["Customer"]
    .astype("category")
    .cat.codes
    .add(1)
    .astype("int64")
)

#create cardID for PII obfuscation
df["Card_ID"] = (
    df["Card_Number"]
    .astype("category")
    .cat.codes
    .add(1)
    .astype("int64")
)

#add prefixes for clarity
df["Customer_ID"] = "CUST_" + df["Customer_ID"].astype(str)
df["Card_ID"] = "CARD_" + df["Card_ID"].astype(str)

#drop PII columns before final export to CSV
df.drop(columns=["Customer", "Card_Number"], inplace=True)

# Save the cleaned, PII-free dataframe
df.to_csv("data/car_sales_data_cleaned.csv", index=False)

print("Import, column conversion, obfuscation and verification completed with no errors")