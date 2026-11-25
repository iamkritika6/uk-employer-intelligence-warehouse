-- Raw table for the Companies House Free Company Data Product.
--
-- 55 columns, matching the header row of the downloaded CSV exactly in order.
-- Names are the file's own, converted to snake_case: the dots in names like
-- "RegAddress.PostTown" and "SICCode.SicText_1" are not valid in an unquoted
-- SQL identifier, so they become underscores.
--
-- The column list was taken from the header row of the file itself, not from
-- the field-list PDF that Companies House links, whose embedded metadata shows
-- it was last modified in 2016.
--
-- Worth knowing: several names in the real header carry a leading space, for
-- example " CompanyNumber" and " ConfStmtLastMadeUpDate". That does not affect
-- the load because COPY is given an explicit column list and skips the header
-- line, but it would break any tool that trusted the header blindly.
--
-- Every column is text. Dates in this file are DD/MM/YYYY, which PostgreSQL
-- will not read as dates under default settings, and several numeric columns
-- are blank for some companies. Both are converted in staging, where a bad
-- value can be reported instead of aborting a 5-million-row load.

CREATE TABLE IF NOT EXISTS raw.companies (
    company_name                          text,
    company_number                        text,
    reg_address_care_of                   text,
    reg_address_po_box                    text,
    reg_address_address_line1             text,
    reg_address_address_line2             text,
    reg_address_post_town                 text,
    reg_address_county                    text,
    reg_address_country                   text,
    reg_address_post_code                 text,
    company_category                      text,
    company_status                        text,
    country_of_origin                     text,
    dissolution_date                      text,
    incorporation_date                    text,
    accounts_account_ref_day              text,
    accounts_account_ref_month            text,
    accounts_next_due_date                text,
    accounts_last_made_up_date            text,
    accounts_account_category             text,
    returns_next_due_date                 text,
    returns_last_made_up_date             text,
    mortgages_num_mort_charges            text,
    mortgages_num_mort_outstanding        text,
    mortgages_num_mort_part_satisfied     text,
    mortgages_num_mort_satisfied          text,
    sic_code_sic_text_1                   text,
    sic_code_sic_text_2                   text,
    sic_code_sic_text_3                   text,
    sic_code_sic_text_4                   text,
    limited_partnerships_num_gen_partners text,
    limited_partnerships_num_lim_partners text,
    uri                                   text,
    previous_name_1_condate               text,
    previous_name_1_company_name          text,
    previous_name_2_condate               text,
    previous_name_2_company_name          text,
    previous_name_3_condate               text,
    previous_name_3_company_name          text,
    previous_name_4_condate               text,
    previous_name_4_company_name          text,
    previous_name_5_condate               text,
    previous_name_5_company_name          text,
    previous_name_6_condate               text,
    previous_name_6_company_name          text,
    previous_name_7_condate               text,
    previous_name_7_company_name          text,
    previous_name_8_condate               text,
    previous_name_8_company_name          text,
    previous_name_9_condate               text,
    previous_name_9_company_name          text,
    previous_name_10_condate              text,
    previous_name_10_company_name         text,
    conf_stmt_next_due_date               text,
    conf_stmt_last_made_up_date           text,
    source_file                           text,
    loaded_at                             timestamptz DEFAULT now()
);
