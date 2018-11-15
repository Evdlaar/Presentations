
-- Let's take a look at the data
SELECT * FROM automobile

-- To train and measure the performance of our model we are going to split the dataset
-- Select 10% of the rows into a new test table
-- We are using these to test our model accuracy
SELECT TOP 10 PERCENT * 
INTO Automobile_test
FROM Automobile

-- Place the remaining 90% into a train table
-- This data will be used to train the model
SELECT * 
INTO Automobile_train
FROM Automobile
EXCEPT
SELECT TOP 10 PERCENT * FROM Automobile

-- We are going to store our Machine Learning model inside a SQL Server table!
-- Create a table to hold our model
CREATE TABLE models 
	( 
    model_name nvarchar(100) not null,
    model_version nvarchar(100) not null,
    model_object varbinary(max) not null
    )
 GO

-- We are going to train our model using R in combination with
-- the sp_execute_external_script method
-- First we need to make sure external scripts are enabled
EXEC sp_configure 'external scripts enabled',1
RECONFIGURE WITH OVERRIDE
GO

-- Let's train a model from inside SQL Server using R!!
DECLARE @model VARBINARY(MAX)

EXEC sp_execute_external_script  
	@language = N'R', -- language R/Python
    @script = N'  
		        automobiles.linmod <- rxLinMod(price ~ wheel_base + length + width + height + curb_weight + engine_size + horsepower, data = automobiles)             
                model <- rxSerializeModel(automobiles.linmod, realtimeScoringOnly = FALSE)', -- model train code
	@input_data_1 = N'SELECT * FROM Automobile_Train', -- input dataset
	@input_data_1_name = N'automobiles', -- name of the input dataset used in the R code
	@params = N'@model varbinary(max) OUTPUT', -- output parameter name and type
	@model = @model OUTPUT -- mapping output to variable

-- We use rxSerializeModel to be able to store it as a VARBINARY
-- it is also required for the other predict options

-- Insert the model in the table we created
INSERT models
	(
	model_name, 
	model_version, 
	model_object
	)
 VALUES
	(
	'automobiles.linmod',
	'v1', 
	@model
	)

-- See what it looks like
SELECT * FROM models


/* ---------------------------------------
        sp_execute_external_script
----------------------------------------*/

-- With our model stored inside the database itself, let's use it to do some predictions!
-- In this case we are using the data inside the automobile_test table we created earlier

-- Grab the stored model from the table and set it to a variable
DECLARE @lin_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'automobiles.linmod')

EXECUTE sp_execute_external_script
               @language = N'R',
               @script = N'
                          model = rxUnserializeModel(lin_model);
                          automobiles_prediction = rxPredict(model, data=automobiles_test)
                          automobiles_pred_results <- cbind(automobiles_test, automobiles_prediction)',
               @input_data_1 = N'  
                                 SELECT
                                   wheel_base,
                                   length,
                                   width,
                                   height,
                                   curb_weight,
                                   engine_size,
                                   horsepower,
                                   price  
                                 FROM Automobile_Test',
               @input_data_1_name = N'automobiles_test',
               @output_data_1_name = N'automobiles_pred_results',
               @params = N'@lin_model varbinary(max)',
               @lin_model = @lin_model_raw
 WITH RESULT SETS (("wheel_base" FLOAT, "length" FLOAT, "width" FLOAT, "height" FLOAT, "curb_weight" FLOAT, "engine_size" FLOAT, "horsepower" FLOAT, "price" FLOAT, "predicted_price" FLOAT))

 
/* ---------------------------------------
               sp_rxPredict
----------------------------------------*/

-- We can use the same model as input for the sp_rxPredict option
-- But before we can use it we need to do a couple of things 
-- (incl. enabling CLR integration, setting db to trustworthy)  
-- which are written down here: https://bit.ly/2sVFTbH

-- Grab the model from the model table
DECLARE @lin_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'automobiles.linmod')

-- Score our test data against the model using sp_rxPredict
-- Notice we can only return the predicted value
EXEC sp_rxPredict 
	@model = @lin_model_raw,
	@inputData = N'  
				   SELECT
					wheel_base,
					length,
					width,
					height,
					curb_weight,
					engine_size,
					horsepower,
					price 
				  FROM Automobile_Test'

/* ---------------------------------------
               PREDICT
----------------------------------------*/

-- Last option is using the PREDICT function thats available in SQL Server 2017
-- Again we start by grabbing the model from the model table
DECLARE @lin_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'automobiles.linmod')

-- This time we do not call a Stored Procedure
-- Instead we call the model through the TSQL syntax
SELECT 
  a.*, 
  p.*
FROM PREDICT(MODEL = @lin_model_raw, DATA = dbo.Automobile_test as a)
WITH("price_Pred" float) as p;

-- Cleanup
DROP TABLE Automobile_test
DROP TABLE Automobile_train
DROP TABLE models

