USE [master];
GO

-- 1. Create a server-level SQL Server Login matching your exact naming convention
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


-- Scalar Function to compute rates automatically
CREATE FUNCTION dbo.fn_calculate_booking_cost(
    @p_customer_id INT,
    @p_zone_id INT,
    @p_coach_id INT,
    @p_duration_hours DECIMAL(5,2)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @v_base_rate DECIMAL(10,2);
    DECLARE @v_coach_rate DECIMAL(10,2) = 0;
    DECLARE @v_discount_pct DECIMAL(5,2);
    DECLARE @v_final_cost DECIMAL(10,2);

    SELECT @v_base_rate = base_hourly_rate FROM sport_zones WHERE zone_id = @p_zone_id;
    
    IF @p_coach_id IS NOT NULL
        SELECT @v_coach_rate = hourly_rate FROM coaches WHERE coach_id = @p_coach_id;
        
    SELECT @v_discount_pct = mt.discount_pct 
    FROM customers c 
    JOIN membership_tiers mt ON c.tier_id = mt.tier_id
    WHERE c.customer_id = @p_customer_id;

    SET @v_final_cost = ((@v_base_rate + @v_coach_rate) * @p_duration_hours);
    SET @v_final_cost = @v_final_cost - (@v_final_cost * (@v_discount_pct / 100.00));

    RETURN @v_final_cost;
END;
GO

-- Transaction-safe Booking Assignment Stored Procedure
CREATE PROCEDURE dbo.sp_create_reservation
    @p_customer_id INT,
    @p_zone_id INT,
    @p_coach_id INT,
    @p_start_time DATETIME,
    @p_end_time DATETIME
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @v_conflict_count INT;
    DECLARE @v_duration_hours DECIMAL(5,2);
    DECLARE @v_total_calculated_cost DECIMAL(10,2);
    DECLARE @v_next_id INT;

    -- Time sequence logic handling
    IF @p_end_time <= @p_start_time
    BEGIN
        RAISERROR('End timestamp must be strictly after start timestamp.', 16, 1);
        RETURN;
    END

    -- Check for timeline conflicts (Simulates Oracle Cursor Check)
    SELECT @v_conflict_count = COUNT(*) 
    FROM bookings 
    WHERE zone_id = @p_zone_id
      AND payment_status != 'CANCELLED'
      AND (@p_start_time < end_time AND @p_end_time > start_time);

    IF @v_conflict_count > 0
    BEGIN
        RAISERROR('Resource allocation failure: Selected Sport Zone is occupied for this timeline.', 16, 1);
        RETURN;
    END

    -- Compute clean duration metric
    SET @v_duration_hours = DATEDIFF(MINUTE, @p_start_time, @p_end_time) / 60.0;
    
    -- Call our cost tracking function
    SET @v_total_calculated_cost = dbo.fn_calculate_booking_cost(@p_customer_id, @p_zone_id, @p_coach_id, @v_duration_hours);
    
    -- Derive next non-identity dynamic Primary Key
    SELECT @v_next_id = ISNULL(MAX(booking_id), 0) + 1 FROM bookings;

    -- Core Transaction Wrap Block
    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO bookings (booking_id, customer_id, zone_id, coach_id, booking_date, start_time, end_time, total_cost, payment_status)
        VALUES (@v_next_id, @p_customer_id, @p_zone_id, @p_coach_id, GETDATE(), @p_start_time, @p_end_time, @v_total_calculated_cost, 'PENDING');
        
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- 1. Security Trigger Block (Blocks Weekday & Holiday Alterations)
CREATE TRIGGER trg_secure_dml_governance
ON bookings
INSTEAD OF INSERT, UPDATE, DELETE
AS
BEGIN
    DECLARE @v_holiday_match INT;
    DECLARE @v_day_of_week INT;

    -- SQL Server DATEPART (1 = Sunday, 2 = Monday... 6 = Friday, 7 = Saturday)
    SET @v_day_of_week = DATEPART(WEEKDAY, GETDATE());

    SELECT @v_holiday_match = COUNT(*) 
    FROM holiday_reference 
    WHERE CAST(holiday_date AS DATE) = CAST(GETDATE() AS DATE);

    IF (@v_holiday_match > 0) OR (@v_day_of_week BETWEEN 2 AND 6)
    BEGIN
        RAISERROR('Security Error: Data transactional mutations on Bookings are highly controlled during normal operating weekdays and registered holidays.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END;
GO

-- 2. Security Audit Trail Capture Trigger
CREATE TRIGGER trg_audit_bookings_activity
ON bookings
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @v_action VARCHAR(10);

    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted)
        SET @v_action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted)
        SET @v_action = 'INSERT';
    ELSE
        SET @v_action = 'DELETE';

    INSERT INTO system_audit_trail (action_type, target_table)
    VALUES (@v_action, 'BOOKINGS');
END;
GO

-- 3. Phase V.2 Innovation Data Feed Reporting View 
CREATE VIEW vw_analytics_revenue_efficiency AS
SELECT 
    sz.zone_name,
    sz.sport_type,
    SUM(b.total_cost) AS total_gross_revenue,
    COUNT(b.booking_id) AS total_slots_booked,
    AVG(DATEDIFF(MINUTE, b.start_time, b.end_time) / 60.0) AS average_utilization_hours
FROM sport_zones sz
LEFT JOIN bookings b ON sz.zone_id = b.zone_id
WHERE b.payment_status IN ('COMPLETED', 'PENDING')
GROUP BY sz.zone_name, sz.sport_type;
GO


-- Desactivate operational trigger constraints temporarily for evaluation verification runs
ALTER TABLE bookings DISABLE TRIGGER trg_secure_dml_governance;
GO

-- Execute the procedure reservation testing parameter
EXEC dbo.sp_create_reservation
    @p_customer_id = 501, 
    @p_zone_id = 104, 
    @p_coach_id = 901, 
    @p_start_time = '2026-07-15 10:00:00', 
    @p_end_time = '2026-07-15 12:00:00';
GO

-- Review programmatic data records and audit logs simultaneously
SELECT * FROM bookings WHERE customer_id = 501;
SELECT * FROM system_audit_trail;
GO

-- Reactivate operational security trigger blocks instantly
ALTER TABLE bookings ENABLE TRIGGER trg_secure_dml_governance;
GO