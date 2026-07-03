-- as admin, in household_test
CREATE ROLE svcbackup LOGIN PASSWORD 'YOUR_PASSWORD_HERE';
CREATE SCHEMA mirror AUTHORIZATION svcbackup;   -- role owns this schema outright