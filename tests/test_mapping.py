"""
test_mapping.py  -  the SQL Server <-> PostgreSQL field map.
"""
import pytest
from replicator import mapping


def test_all_expected_tables_present():
    tables = mapping.replicated_tables()
    assert len(tables) == 12
    assert "dbo.DimUsers" in tables
    assert "dbo.FactStockTransactions" in tables


def test_pg_table_name_translation():
    assert mapping.pg_table("dbo.DimUsers") == "dim_users"
    assert mapping.pg_table("dbo.FactAccountBrokerMappings") == "fact_account_broker_mappings"


def test_column_pairs_have_matching_lengths():
    for t in mapping.replicated_tables():
        pairs = mapping.column_pairs(t)
        assert len(pairs) > 0
        # every pair is (mssql_name, pg_name), both non-empty
        for mssql_col, pg_col in pairs:
            assert mssql_col and pg_col


def test_pk_is_id_and_first_column():
    for t in mapping.replicated_tables():
        pairs = mapping.column_pairs(t)
        assert pairs[0] == ("ID", "id"), f"{t} first column should be ID->id"


def test_isin_edge_case_snake_case():
    # the acronym-collision case we specifically fixed
    pairs = dict(mapping.column_pairs("dbo.DimMutualFunds"))
    assert pairs["ISINFolioHolderHash"] == "isin_folio_holder_hash"


def test_snake_case_not_smushed():
    # AccountNo must become account_no, not accountno
    pairs = dict(mapping.column_pairs("dbo.DimAccounts"))
    assert pairs["AccountNo"] == "account_no"


def test_is_replicated():
    assert mapping.is_replicated("dbo.DimUsers") is True
    assert mapping.is_replicated("dbo.NotARealTable") is False


def test_mssql_and_pg_column_helpers_align():
    t = "dbo.DimUsers"
    mssql_cols = mapping.mssql_columns(t)
    pg_cols = mapping.pg_columns(t)
    assert len(mssql_cols) == len(pg_cols)
    # order preserved
    assert mssql_cols[0] == "ID"
    assert pg_cols[0] == "id"


def test_unknown_table_raises_keyerror():
    with pytest.raises(KeyError):
        mapping.pg_table("dbo.DoesNotExist")
