PHASE IV: DATABASE CREATION 
 1. Create a server-level SQL Server Login matching your exact naming convention
-- Format: StudentID_FirstName_Project_DB
CREATE LOGIN [27744_2024_Cyr_SportConnect_DB] 
WITH PASSWORD = '9999', 
     DEFAULT_DATABASE = [27744_2024_Cyr_SportConnect_DB], 
     CHECK_EXPIRATION = OFF, 
     CHECK_POLICY = OFF;
GO

USE [27744_2024_Cyr_SportConnect_DB];
GO

-- 2. Create the Database User mapped directly to that Login
CREATE USER [27744_2024_Cyr_SportConnect_DB] 
FOR LOGIN [27744_2024_Cyr_SportConnect_DB];
GO

-- 3. Phase IV Requirement: Assign Privileges & Configure Access
-- Grants the user full administrative schema permissions within this specific database
ALTER ROLE [db_owner] ADD MEMBER [27744_2024_Cyr_SportConnect_DB];
GO
-- 1. Membership Tiers Lookup Table
CREATE TABLE membership_tiers (
    tier_id INT PRIMARY KEY,
    tier_name VARCHAR(50) NOT NULL UNIQUE,
    discount_pct DECIMAL(5,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 100),
    monthly_fee DECIMAL(10,2) NOT NULL CHECK (monthly_fee >= 0)
);

-- 2. Customers Table
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE CHECK (email LIKE '%_@__%.__%'), -- Standard T-SQL pattern validation
    phone VARCHAR(20) NOT NULL,
    tier_id INT NOT NULL,
    registration_date DATETIME DEFAULT GETDATE() NOT NULL,
    CONSTRAINT fk_cust_tier FOREIGN KEY (tier_id) REFERENCES membership_tiers(tier_id)
);

-- 3. Coaches Table
CREATE TABLE coaches (
    coach_id INT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    hourly_rate DECIMAL(10,2) NOT NULL CHECK (hourly_rate > 0),
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

-- 4. Sport Zones (Facilities) Table
CREATE TABLE sport_zones (
    zone_id INT PRIMARY KEY,
    zone_name VARCHAR(100) NOT NULL UNIQUE,
    sport_type VARCHAR(50) NOT NULL,
    base_hourly_rate DECIMAL(10,2) NOT NULL CHECK (base_hourly_rate >= 0),
    max_capacity INT NOT NULL CHECK (max_capacity > 0)
);

-- 5. Holiday Reference Table (Phase VII Security Metric)
CREATE TABLE holiday_reference (
    holiday_date DATE PRIMARY KEY,
    holiday_name VARCHAR(100) NOT NULL
);

-- 6. Bookings Transactional Table
CREATE TABLE bookings (
    booking_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    zone_id INT NOT NULL,
    coach_id INT NULL,
    booking_date DATETIME DEFAULT GETDATE() NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    total_cost DECIMAL(10,2) NOT NULL CHECK (total_cost >= 0),
    payment_status VARCHAR(20) DEFAULT 'PENDING' CHECK (payment_status IN ('PENDING', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT fk_book_cust FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_book_zone FOREIGN KEY (zone_id) REFERENCES sport_zones(zone_id),
    CONSTRAINT fk_book_coach FOREIGN KEY (coach_id) REFERENCES coaches(coach_id),
    CONSTRAINT chk_booking_times CHECK (end_time > start_time)
);

-- 7. System Audit Trail Logging Table
CREATE TABLE system_audit_trail (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    username VARCHAR(100) DEFAULT ORIGINAL_LOGIN(),
    action_type VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    target_table VARCHAR(50) NOT NULL,
    performed_at DATETIME DEFAULT GETDATE() NOT NULL,
    terminal_info VARCHAR(255) DEFAULT HOST_NAME()
);
GO
PHASE V: TABLE IMPLEMENTATION 
-- Drop tables if they already exist to ensure clean re-deployment execution
IF OBJECT_ID('system_audit_trail', 'U') IS NOT NULL DROP TABLE system_audit_trail;
IF OBJECT_ID('bookings', 'U') IS NOT NULL DROP TABLE bookings;
IF OBJECT_ID('holiday_reference', 'U') IS NOT NULL DROP TABLE holiday_reference;
IF OBJECT_ID('sport_zones', 'U') IS NOT NULL DROP TABLE sport_zones;
IF OBJECT_ID('coaches', 'U') IS NOT NULL DROP TABLE coaches;
IF OBJECT_ID('customers', 'U') IS NOT NULL DROP TABLE customers;
IF OBJECT_ID('membership_tiers', 'U') IS NOT NULL DROP TABLE membership_tiers;
GO

-- 1. Membership Tiers Lookup Table
CREATE TABLE membership_tiers (
    tier_id INT PRIMARY KEY,
    tier_name VARCHAR(50) NOT NULL UNIQUE,
    discount_pct DECIMAL(5,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 100),
    monthly_fee DECIMAL(10,2) NOT NULL CHECK (monthly_fee >= 0)
);

-- 2. Customers Table
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE CHECK (email LIKE '%_@__%.__%'), -- Standard T-SQL pattern validation
    phone VARCHAR(20) NOT NULL,
    tier_id INT NOT NULL,
    registration_date DATETIME DEFAULT GETDATE() NOT NULL,
    CONSTRAINT fk_cust_tier FOREIGN KEY (tier_id) REFERENCES membership_tiers(tier_id)
);

-- 3. Coaches Table
CREATE TABLE coaches (
    coach_id INT PRIMARY KEY,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    specialization VARCHAR(100) NOT NULL,
    hourly_rate DECIMAL(10,2) NOT NULL CHECK (hourly_rate > 0),
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

-- 4. Sport Zones (Facilities) Table
CREATE TABLE sport_zones (
    zone_id INT PRIMARY KEY,
    zone_name VARCHAR(100) NOT NULL UNIQUE,
    sport_type VARCHAR(50) NOT NULL,
    base_hourly_rate DECIMAL(10,2) NOT NULL CHECK (base_hourly_rate >= 0),
    max_capacity INT NOT NULL CHECK (max_capacity > 0)
);

-- 5. Holiday Reference Table (Phase VII Security Metric)
CREATE TABLE holiday_reference (
    holiday_date DATE PRIMARY KEY,
    holiday_name VARCHAR(100) NOT NULL
);

-- 6. Bookings Transactional Table
CREATE TABLE bookings (
    booking_id INT PRIMARY KEY,
    customer_id INT NOT NULL,
    zone_id INT NOT NULL,
    coach_id INT NULL,
    booking_date DATETIME DEFAULT GETDATE() NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    total_cost DECIMAL(10,2) NOT NULL CHECK (total_cost >= 0),
    payment_status VARCHAR(20) DEFAULT 'PENDING' CHECK (payment_status IN ('PENDING', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT fk_book_cust FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_book_zone FOREIGN KEY (zone_id) REFERENCES sport_zones(zone_id),
    CONSTRAINT fk_book_coach FOREIGN KEY (coach_id) REFERENCES coaches(coach_id),
    CONSTRAINT chk_booking_times CHECK (end_time > start_time)
);

-- 7. System Audit Trail Logging Table
CREATE TABLE system_audit_trail (
    audit_id INT IDENTITY(1,1) PRIMARY KEY,
    username VARCHAR(100) DEFAULT ORIGINAL_LOGIN(),
    action_type VARCHAR(10) NOT NULL, -- INSERT, UPDATE, DELETE
    target_table VARCHAR(50) NOT NULL,
    performed_at DATETIME DEFAULT GETDATE() NOT NULL,
    terminal_info VARCHAR(255) DEFAULT HOST_NAME()
);
GO

-- Populate Master/Reference Data
INSERT INTO membership_tiers VALUES (1, 'Standard', 0.00, 0.00),
                                    (2, 'Silver', 10.00, 25000.00),
                                    (3, 'Gold', 20.00, 45000.00);

INSERT INTO holiday_reference VALUES ('2026-01-01', 'New Years Day'),
                                    ('2026-02-01', 'National Heroes Day'),
                                    ('2026-04-07', 'Genocide Memorial Day'),
                                    ('2026-07-01', 'Independence Day');

INSERT INTO sport_zones VALUES (101, 'Main Football Turf', 'Football', 30000.00, 22),
                               (102, 'Indoor Basketball Court A', 'Basketball', 25000.00, 10),
                               (103, 'Olympic Swimming Pool', 'Swimming', 15000.00, 30),
                               (104, 'Tennis Court Clay', 'Tennis', 20000.00, 4);

INSERT INTO customers VALUES (501, 'Alain', 'Mugisha', 'alain.m@domain.rw', '+250788123456', 3, '2026-01-15'),
                             (502, 'Sonia', 'Uwase', 'sonia.u@domain.rw', '+250788654321', 1, '2026-02-10');

INSERT INTO coaches VALUES (901, 'Jean_Paul', 'Ndayisaba', 'Tennis', 15000.00, 'ACTIVE'),
                           (902, 'Sandrine', 'Umubyeyi', 'Swimming', 12000.00, 'ACTIVE');
GO
PHASE VI: PL/SQL PROGRAMMING 

PHASE VII: ADVANCED DATABASE PROGRAMMING
