# Table & Column Mapping — SQL Server ↔ PostgreSQL

SQL Server side: **LocalTestDB** (test) / **LocalProdDB** (prod).  
PostgreSQL side: **household_test** (test) / **household_prod** (prod).

**Authority:** PostgreSQL names and types are taken from `schema.sql` (the deployed DDL). This file is the single source both the consumer and the DDL must agree with.

### Design decisions baked in
- **Option A keys** — PostgreSQL `id` carries the SQL Server `ID` verbatim; the consumer inserts it explicitly.
- **FK-free mirror** — the `dim_users_s → dim_users` foreign key and its `ON DELETE CASCADE` are intentionally **omitted** on the PostgreSQL side, so the consumer's atomic swap can use plain `TRUNCATE`. (See action note at bottom.)
- **VARBINARY → bytea** — carried as raw bytes, never decoded.

## `dbo.DimAccounts`  →  `dim_accounts`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| AccountNo | account_no | bytea |
| AccountNoHash | account_no_hash | bytea |
| EntityId | entity_id | integer |
| AccountType | account_type | text |
| FirstHolderId | first_holder_id | integer |
| JointHolder1Id | joint_holder1_id | integer |
| JointHolder2Id | joint_holder2_id | integer |
| OperationType | operation_type | text |
| FirstHolderAddress | first_holder_address | bytea |
| Nominee1Id | nominee1_id | integer |
| Nominee2Id | nominee2_id | integer |
| CIF | cif | bytea |
| MinimumBalance | minimum_balance | numeric(18,2) |
| OpenYear | open_year | bytea |
| ChequeBookCount | cheque_book_count | integer |
| EmailId | email_id | bytea |
| ContactNo | contact_no | bytea |
| IsActive | is_active | boolean |
| PassbookAvailable | passbook_available | boolean |
| OnlineBankingAllowed | online_banking_allowed | boolean |
| OnlineLoginAvailable | online_login_available | boolean |
| AadharLinked | aadhar_linked | boolean |
| BrokersLinked | brokers_linked | boolean |
| Comments | comments | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.DimEntities`  →  `dim_entities`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| EntityNameHash | entity_name_hash | bytea |
| EntityName | entity_name | bytea |
| EntityBranch | entity_branch | bytea |
| AddressLine1 | address_line1 | bytea |
| AddressLine2 | address_line2 | bytea |
| City | city | bytea |
| PostCode | post_code | bytea |
| Country | country | bytea |
| CustomerCareEmailId | customer_care_email_id | bytea |
| CustomerCarePhoneNo | customer_care_phone_no | bytea |
| CustomerCareWebsite | customer_care_website | bytea |
| IFSC | ifsc | bytea |
| MICR | micr | bytea |
| SWIFT | swift | bytea |
| IBAN | iban | bytea |
| EntityType | entity_type | varchar(5) |
| IsOnline | is_online | boolean |
| RegistrarId | registrar_id | integer |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.DimMutualFunds`  →  `dim_mutual_funds`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| ISINFolioHolderHash | isin_folio_holder_hash | bytea |
| FolioNo | folio_no | bytea |
| SchemeName | scheme_name | bytea |
| ISIN | isin | bytea |
| SchemeCode | scheme_code | bytea |
| SchemeCategory | scheme_category | bytea |
| FirstHolderId | first_holder_id | integer |
| JointHolder1Id | joint_holder1_id | integer |
| JointHolder2Id | joint_holder2_id | integer |
| Nominee1Id | nominee1_id | integer |
| Nominee2Id | nominee2_id | integer |
| OperationMode | operation_mode | varchar(20) |
| TotalUnitsBought | total_units_bought | numeric(11,4) |
| TotalUnitsSold | total_units_sold | numeric(11,4) |
| TotalUnitsHeld | total_units_held | numeric(11,4) |
| TotalInvestedAmount | total_invested_amount | numeric(11,2) |
| TotalRedeemedAmount | total_redeemed_amount | numeric(11,2) |
| TotalDividendReceived | total_dividend_received | numeric(11,2) |
| IsActive | is_active | boolean |
| LinkedEntityId | linked_entity_id | integer |
| IsDividend | is_dividend | boolean |
| IsOnline | is_online | boolean |
| IsDemat | is_demat | boolean |
| Comments | comments | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.DimUsers`  →  `dim_users`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| UserNameHash | user_name_hash | bytea |
| Gender | gender | char(1) |
| Age | age | integer |
| FatherId | father_id | integer |
| MotherId | mother_id | integer |
| SpouseId | spouse_id | integer |
| MaritalStatus | marital_status | char(1) |
| IsExpired | is_expired | boolean |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.DimUsers_S`  →  `dim_users_s`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| UserID | user_id | integer |
| FirstName | first_name | bytea |
| LastName | last_name | bytea |
| BirthDate | birth_date | bytea |
| BirthCity | birth_city | bytea |
| BirthCountry | birth_country | bytea |
| MarriageDate | marriage_date | bytea |
| CurrentAddressLine1 | current_address_line1 | bytea |
| CurrentAddressLine2 | current_address_line2 | bytea |
| CurrentCity | current_city | bytea |
| CurrentPostCode | current_post_code | bytea |
| CurrentCountry | current_country | bytea |
| PermanentAddressLine1 | permanent_address_line1 | bytea |
| PermanentAddressLine2 | permanent_address_line2 | bytea |
| PermanentCity | permanent_city | bytea |
| PermanentPostCode | permanent_post_code | bytea |
| PermanentCountry | permanent_country | bytea |
| ContactEmailId | contact_email_id | bytea |
| ContactMobileNo | contact_mobile_no | bytea |
| ContactPhoneNo | contact_phone_no | bytea |
| WorkEmailId | work_email_id | bytea |
| WorkMobileNo | work_mobile_no | bytea |
| WorkPhoneNo | work_phone_no | bytea |
| ExpiredDate | expired_date | bytea |
| PAN | pan | bytea |
| Aadhar | aadhar | bytea |
| TIN | tin | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactAccountBrokerMappings`  →  `fact_account_broker_mappings`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| AccountId | account_id | integer |
| BrokerId | broker_id | integer |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactAliases`  →  `fact_aliases`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| RecordType | record_type | varchar(50) |
| RecordId | record_id | integer |
| AliasName | alias_name | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactDeposits`  →  `fact_deposits`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| DepositNo | deposit_no | bytea |
| DepositNoHash | deposit_no_hash | varchar(64) |
| EntityId | entity_id | integer |
| LinkedAccountId | linked_account_id | integer |
| FirstHolderId | first_holder_id | integer |
| JointHolder1Id | joint_holder1_id | integer |
| JointHolder2Id | joint_holder2_id | integer |
| OperationType | operation_type | varchar(10) |
| Nominee1Id | nominee1_id | integer |
| Nominee2Id | nominee2_id | integer |
| InvestedAmount | invested_amount | numeric(11,2) |
| InterestRate | interest_rate | numeric(4,2) |
| StartDate | start_date | timestamp |
| ExpectedMaturityDate | expected_maturity_date | timestamp |
| PeriodYears | period_years | integer |
| PeriodMonths | period_months | integer |
| PeriodDays | period_days | integer |
| ExpectedMaturityAmount | expected_maturity_amount | numeric(11,2) |
| ExpectedInterestAmount | expected_interest_amount | numeric(11,2) |
| ActualInterestAmount | actual_interest_amount | numeric(11,2) |
| ActualMaturityDate | actual_maturity_date | timestamp |
| ActualMaturityAmount | actual_maturity_amount | numeric(11,2) |
| DepositCurrency | deposit_currency | varchar(10) |
| DepositType | deposit_type | varchar(10) |
| InterestPaymentFrequency | interest_payment_frequency | varchar(10) |
| DepositPaymentFrequency | deposit_payment_frequency | varchar(10) |
| ClosureType | closure_type | varchar(10) |
| IsBookedOnline | is_booked_online | boolean |
| IsAutoRenewable | is_auto_renewable | boolean |
| IsRenewed | is_renewed | boolean |
| IsActive | is_active | boolean |
| IsPrematureWithdrawal | is_premature_withdrawal | boolean |
| BrokerId | broker_id | integer |
| Comments | comments | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactMutualFundTransactions`  →  `fact_mutual_fund_transactions`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| FundId | fund_id | integer |
| TransactionOrderHash | transaction_order_hash | bytea |
| Exchange | exchange | varchar(10) |
| TransactionDate | transaction_date | timestamp |
| TransactionType | transaction_type | varchar(10) |
| RealizedAmount | realized_amount | numeric(11,2) |
| TransactionAmount | transaction_amount | numeric(11,2) |
| TransactionNAV | transaction_nav | numeric(11,4) |
| TransactionUnits | transaction_units | numeric(11,4) |
| TransactionSTT | transaction_stt | numeric(11,2) |
| TransactionTDS | transaction_tds | numeric(11,2) |
| TransactionStampDuty | transaction_stamp_duty | numeric(11,2) |
| BrokerId | broker_id | integer |
| OrderId | order_id | bytea |
| TradeId | trade_id | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactOtherContacts`  →  `fact_other_contacts`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| RecordType | record_type | varchar(50) |
| ContactType | contact_type | varchar(50) |
| RecordId | record_id | integer |
| ContactValue | contact_value | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |

## `dbo.FactStockTransactions`  →  `fact_stock_transactions`

| SQL Server column | PostgreSQL column | PG type |
|---|---|---|
| ID | id | integer |
| TradeOrderHash | trade_order_hash | bytea |
| HolderId | holder_id | integer |
| Symbol | symbol | bytea |
| ISIN | isin | bytea |
| Exchange | exchange | varchar(10) |
| TradeDate | trade_date | timestamp |
| TradeType | trade_type | varchar(10) |
| TradeAmount | trade_amount | numeric(11,2) |
| TradePrice | trade_price | numeric(11,2) |
| TradeQuantity | trade_quantity | numeric(11,2) |
| NomineeId | nominee_id | integer |
| LinkedEntityId | linked_entity_id | integer |
| BrokerId | broker_id | integer |
| OrderId | order_id | bytea |
| TradeId | trade_id | bytea |
| CreatedDate | created_date | timestamp |
| ModifiedDate | modified_date | timestamp |
