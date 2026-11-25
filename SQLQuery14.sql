USE [Alati vezbanje];
GO

CREATE OR ALTER VIEW dbo.vw_SalesAnalysis
AS
SELECT
    s.SalesOrderNumber,
    TRY_CONVERT(date,
        CASE
            WHEN CHARINDEX(',', CONVERT(nvarchar(100), s.OrderDate)) > 0
            THEN LTRIM(SUBSTRING(CONVERT(nvarchar(100), s.OrderDate),
                                 CHARINDEX(',', CONVERT(nvarchar(100), s.OrderDate)) + 1, 100))
            ELSE CONVERT(nvarchar(100), s.OrderDate) -- fixao gpt nece da konvertuje
        END, 107) AS OrderDate,
    s.ProductKey,
    p.Product,
    p.Category,
    p.Subcategory,
    p.Color,
    s.ResellerKey,
    r.Reseller,
    r.[Business_Type] AS BusinessType,
    r.City,
    r.[State_Province] AS StateProvince,
    r.[Country_Region] AS CountryRegion,
    s.EmployeeKey,
    sp.Salesperson,
    sp.Title AS SalespersonTitle,
    s.SalesTerritoryKey,
    rg.Region,
    rg.Country,
    rg.[Group] AS RegionGroup,
    TRY_CONVERT(int, s.Quantity) AS Quantity,
    TRY_CONVERT(decimal(18,2),
        REPLACE(REPLACE(CONVERT(nvarchar(50), s.[Unit_Price]), '$', ''), ',', '')) AS UnitPrice,
    TRY_CONVERT(decimal(18,2),
        REPLACE(REPLACE(CONVERT(nvarchar(50), s.Sales), '$', ''), ',', '')) AS SalesAmount,
    TRY_CONVERT(decimal(18,2),
        REPLACE(REPLACE(CONVERT(nvarchar(50), s.Cost), '$', ''), ',', '')) AS CostAmount
FROM dbo.Sales AS s
INNER JOIN dbo.Product AS p
    ON s.ProductKey = p.ProductKey
INNER JOIN dbo.Reseller AS r
    ON s.ResellerKey = r.ResellerKey
INNER JOIN dbo.Salesperson AS sp
    ON s.EmployeeKey = sp.EmployeeKey
INNER JOIN dbo.Region AS rg
    ON s.SalesTerritoryKey = rg.SalesTerritoryKey;
GO

-- provera
SELECT
    COUNT(*) AS BrojRedova
FROM dbo.vw_SalesAnalysis;
GO


/*
1. PRVIH / POSLEDNJIH N TORKI
*/
CREATE OR ALTER VIEW dbo.vw_Top5Prodavaca
AS
SELECT TOP (5)
    v.Salesperson,
    v.SalespersonTitle AS Title,
    COUNT(DISTINCT v.SalesOrderNumber) AS NumberOfOrders,
    SUM(v.SalesAmount) AS TotalSales
FROM dbo.vw_SalesAnalysis AS v
GROUP BY v.EmployeeKey, v.Salesperson, v.SalespersonTitle
ORDER BY SUM(v.SalesAmount) DESC;
GO
-- npr za davanje bonusa za najboljih 5


-- provera
SELECT * FROM dbo.vw_Top5Prodavaca ORDER BY TotalSales DESC;

-- prvih 10 i poslednjih 10 prodajnih stavki po datumu (isti zahtev, hronoloski)
SELECT TOP (10) *
FROM dbo.vw_SalesAnalysis
WHERE OrderDate IS NOT NULL
ORDER BY OrderDate ASC, SalesOrderNumber ASC;

SELECT TOP (10) *
FROM dbo.vw_SalesAnalysis
WHERE OrderDate IS NOT NULL
ORDER BY OrderDate DESC, SalesOrderNumber DESC;
GO

-- nzm da li treba interpretacija ovde ili usmeno:
-- top 5: Linda Mitchell, Jillian Carson, Michael Blythe, Jae Pak, Tsvi Reiter.
-- prva stavka 1.7.2017., poslednja 31.5.2020.


/*
2. TIPOVI SPAJANJA TABELA
*/
CREATE OR ALTER VIEW dbo.vw_TipoviSpajanja
AS
SELECT
    sp.EmployeeKey,
    sp.Salesperson,
    sp.Title,
    rg.Region,
    rg.Country,
    COUNT(*) OVER (PARTITION BY sp.EmployeeKey) AS BrojRegionaProdavca,
    COALESCE(pp.BrojProdajnihStavki, 0) AS BrojProdajnihStavki,
    COALESCE(pp.UkupnaProdaja, 0) AS UkupnaProdajaProdavca   -- ponavlja se po regionu, ne sabirati!
FROM dbo.Salesperson AS sp
INNER JOIN dbo.SalespersonRegion AS spr
    ON spr.EmployeeKey = sp.EmployeeKey
INNER JOIN dbo.Region AS rg
    ON rg.SalesTerritoryKey = spr.SalesTerritoryKey
LEFT JOIN
(
    SELECT EmployeeKey, COUNT(*) AS BrojProdajnihStavki, SUM(SalesAmount) AS UkupnaProdaja
    FROM dbo.vw_SalesAnalysis
    GROUP BY EmployeeKey
) AS pp
    ON pp.EmployeeKey = sp.EmployeeKey;
GO
-- kao npr gledanje koji prodavac je gde koliko prodao i cak koji nije prodao nista gde je inner po regionima a left po prodavcu

-- provera
SELECT * FROM dbo.vw_TipoviSpajanja ORDER BY UkupnaProdajaProdavca DESC, EmployeeKey, Region;

-- inner ce da izbaci prodavca koji nema nijednu prodaju left ostavlja jadnika
SELECT N'INNER JOIN' AS TipSpajanja, COUNT(DISTINCT sp.EmployeeKey) AS BrojProdavaca
FROM dbo.Salesperson AS sp
INNER JOIN dbo.Sales AS s ON s.EmployeeKey = sp.EmployeeKey -- trazice ih izmedju prodaje i prodavca
UNION ALL
SELECT N'LEFT JOIN', COUNT(DISTINCT sp.EmployeeKey)
FROM dbo.Salesperson AS sp
LEFT JOIN dbo.Sales AS s ON s.EmployeeKey = sp.EmployeeKey;
GO
-- jadnik je Brian ali on je kao direktor tkd ono


/*
3. FILTRIRANJE NAD POJEDINACNIM I AGREGIRANIM VREDNOSTIMA
*/
CREATE OR ALTER VIEW dbo.vw_VelikeProdajeEvropa
AS
SELECT
    SalesOrderNumber, OrderDate, Product, Category,
    Reseller, Salesperson, Region, Country, SalesAmount
FROM dbo.vw_SalesAnalysis
WHERE SalesAmount > 5000
  AND RegionGroup = 'Europe';
GO
-- samo sam nad pojedinacnim vrednostima ovde al moze i agregirano

CREATE OR ALTER VIEW dbo.vw_RegioniIznad5M
AS
SELECT
    Region,
    RegionGroup,
    SUM(SalesAmount) AS TotalSales,
    COUNT(DISTINCT SalesOrderNumber) AS NumberOfOrders
FROM dbo.vw_SalesAnalysis
GROUP BY Region, RegionGroup
HAVING SUM(SalesAmount) > 5000000;
GO
-- evo nije me mrzelo

-- provera
SELECT * FROM dbo.vw_VelikeProdajeEvropa ORDER BY SalesAmount DESC;
SELECT * FROM dbo.vw_RegioniIznad5M ORDER BY TotalSales DESC;
GO

/*
4. DISTRIBUTIVNA I ALGEBARSKA FUNKCIJA
*/
CREATE OR ALTER VIEW dbo.vw_ProdajaPoGodini
AS
WITH OrderTotals AS
(
    SELECT
        YEAR(OrderDate) AS SalesYear,
        ResellerKey,
        SalesOrderNumber,
        SUM(SalesAmount) AS OrderTotal
    FROM dbo.vw_SalesAnalysis
    WHERE OrderDate IS NOT NULL
    GROUP BY YEAR(OrderDate), ResellerKey, SalesOrderNumber
)
SELECT
    ot.SalesYear,
    COUNT(*) AS NumberOfOrders,                                                     -- distributivna COUNT
    SUM(ot.OrderTotal) AS TotalSales,                                               -- distributivna SUM
    CAST(AVG(ot.OrderTotal) AS decimal(18,2)) AS AverageOrder                       -- algebarska avg
FROM OrderTotals AS ot
GROUP BY ot.SalesYear;
GO

-- provera
SELECT * FROM dbo.vw_ProdajaPoGodini ORDER BY SalesYear;
GO


/*
5. HOLISTICKE FUNKCIJE MEDIJANA MODUS
*/
CREATE OR ALTER VIEW dbo.vw_MedijanaPoKategoriji
AS
SELECT DISTINCT
    Category,
    COUNT(*) OVER (PARTITION BY Category) AS BrojStavki,
    CAST(AVG(SalesAmount) OVER (PARTITION BY Category) AS decimal(18,2)) AS ProsekStavke,
    CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY SalesAmount)
         OVER (PARTITION BY Category) AS decimal(18,2)) AS MedijanaStavke
FROM dbo.vw_SalesAnalysis
WHERE SalesAmount IS NOT NULL;
GO
-- medijana je percentile cont na 50% pokazuje realnije da li neka stavka izvlaci prosek zato sto je prodato milijardu komada 

-- provera
SELECT * FROM dbo.vw_MedijanaPoKategoriji ORDER BY MedijanaStavke DESC;
GO


/*
6. NAPREDNO GRUPISANJE ROLLUP CUBE
*/
CREATE OR ALTER VIEW dbo.vw_ProdajaRollupRegioni
AS
SELECT
    RegionGroup,
    Country,
    Region,
    SUM(SalesAmount) AS TotalSales
FROM dbo.vw_SalesAnalysis
GROUP BY ROLLUP (RegionGroup, Country, Region);
GO

CREATE OR ALTER VIEW dbo.vw_ProdajaCubeKategorijaGrupa
AS
SELECT
    Category,
    RegionGroup,
    SUM(SalesAmount) AS TotalSales
FROM dbo.vw_SalesAnalysis
GROUP BY CUBE (Category, RegionGroup);     -- isto sto i grouping sets ((Category,RegionGroup),(Category),(RegionGroup),()) samo lepse napisano
GO

SELECT * FROM dbo.vw_ProdajaRollupRegioni
ORDER BY RegionGroup, Country, Region;

SELECT * FROM dbo.vw_ProdajaCubeKategorijaGrupa
ORDER BY Category, RegionGroup;
GO


/*
7. AGREGACIJE WINDOW
*/
CREATE OR ALTER VIEW dbo.vw_MesecnaProdajaPoKategoriji
AS -- pomocni view za ceo tajm lajn i poslednja tri msesca
SELECT
    Category,
    DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1) AS SalesMonth,
    SUM(SalesAmount) AS MonthlySales
FROM dbo.vw_SalesAnalysis
WHERE OrderDate IS NOT NULL
GROUP BY Category, DATEFROMPARTS(YEAR(OrderDate), MONTH(OrderDate), 1);
GO

CREATE OR ALTER VIEW dbo.vw_KumulativnaProdaja -- tj za sve mesece
AS
SELECT
    Category,
    SalesMonth,
    MonthlySales,
    SUM(MonthlySales) OVER (PARTITION BY Category ORDER BY SalesMonth
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeSales, -- od prvog do sadasnjeg reda tj meseca
    AVG(MonthlySales) OVER (PARTITION BY Category ORDER BY SalesMonth
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS AverageToDate
FROM dbo.vw_MesecnaProdajaPoKategoriji;
GO

-- provera
SELECT * FROM dbo.vw_KumulativnaProdaja ORDER BY Category, SalesMonth;
GO


/*
8. WINDOW SA OGRANICENIM DELOM PARTICIJE
*/
CREATE OR ALTER VIEW dbo.vw_PokretniProsek3Meseca
AS
SELECT
    Category,
    SalesMonth,
    MonthlySales,
    AVG(MonthlySales) OVER (PARTITION BY Category ORDER BY SalesMonth
                            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS MovingAverage3Months -- 2 preceding i current je kao poslednja tri isto znaci samo ne moze da se napise last 3
FROM dbo.vw_MesecnaProdajaPoKategoriji;
GO

-- provera
SELECT * FROM dbo.vw_PokretniProsek3Meseca ORDER BY Category, SalesMonth;
GO


/*
9. PIVOT PRE POSLE
*/
CREATE OR ALTER VIEW dbo.vw_ProdajaPoRegionuKategoriji       -- PRE pivota ce prikazati kategorije a mi cemo kategorije da malo transponujemo ovo ono
AS
SELECT
    RegionGroup,
    Category,
    SUM(SalesAmount) AS TotalSales
FROM dbo.vw_SalesAnalysis
GROUP BY RegionGroup, Category;
GO

CREATE OR ALTER VIEW dbo.vw_ProdajaPoRegionuKategorijiPivot  -- POSLE pivota
AS
SELECT RegionGroup, [Bikes], [Components], [Clothing], [Accessories]
FROM
(
    SELECT RegionGroup, Category, TotalSales
    FROM dbo.vw_ProdajaPoRegionuKategoriji
) AS SourceTable
PIVOT
(
    SUM(TotalSales)
    FOR Category IN ([Bikes], [Components], [Clothing], [Accessories])
) AS PivotTable;
GO


-- provera
SELECT * FROM dbo.vw_ProdajaPoRegionuKategoriji ORDER BY RegionGroup, Category;
SELECT * FROM dbo.vw_ProdajaPoRegionuKategorijiPivot ORDER BY RegionGroup;
GO


/*
10. KOMPLEKSAN POGLED
*/
CREATE OR ALTER VIEW dbo.vw_ProfitPoKategorijiRegionu
AS
SELECT
    Category,
    RegionGroup,
    SUM(SalesAmount) AS TotalSales,
    SUM(CostAmount) AS TotalCost,
    SUM(SalesAmount - CostAmount) AS GrossProfit
FROM dbo.vw_SalesAnalysis
GROUP BY Category, RegionGroup;
GO

-- provera
SELECT * FROM dbo.vw_ProfitPoKategorijiRegionu ORDER BY GrossProfit DESC;-- otp gde firma najvise profitira
GO


/*
11. MATERIJALIZACIJA POGLEDA
*/
CREATE OR ALTER PROCEDURE dbo.KreirajMaterijalizovaniPogled
AS
BEGIN
    SET NOCOUNT ON;
    DROP TABLE IF EXISTS dbo.ProfitPoKategorijiRegionu_Mat;

    SELECT *
    INTO dbo.ProfitPoKategorijiRegionu_Mat
    FROM dbo.vw_ProfitPoKategorijiRegionu;
END;
GO


EXEC dbo.KreirajMaterijalizovaniPogled;
GO

-- provera
SELECT * FROM dbo.ProfitPoKategorijiRegionu_Mat ORDER BY GrossProfit DESC;
GO