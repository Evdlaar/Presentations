-- Let's take a look at the data
USE Automobile
GO

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
                model <- rxSerializeModel(automobiles.linmod, realtimeScoringOnly = FALSE)
				
				results <- summary(automobiles.linmod)
				print(results)', -- model train code and return training performance
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
                                   horsepower  
                                 FROM Automobile_Test',
               @input_data_1_name = N'automobiles_test',
               @output_data_1_name = N'automobiles_pred_results',
               @params = N'@lin_model varbinary(max)',
               @lin_model = @lin_model_raw
 WITH RESULT SETS (("wheel_base" FLOAT, "length" FLOAT, "width" FLOAT, "height" FLOAT, "curb_weight" FLOAT, "engine_size" FLOAT, "horsepower" FLOAT, "predicted_price" FLOAT))

-- sp_execute_external_scripts has some added benifits
-- We can run whatever R code we want from SQL Server, including loading libraries!
EXECUTE sp_execute_external_script
               @language = N'R',
               @script = N'
                           library(ggplot2)
						   
						   g <- ggplot(automobile_test, aes(horsepower, price))
						   g + geom_jitter(width = .5, size=1) +
						   labs(y="Price", x="Horsepower", title="Car price vs horsepower")

						   image = tempfile()
						   jpeg(filename = image, width = 800, height = 800)
						   print(g)
						   dev.off()
						   ImgOutput <- data.frame(data=readBin(file(image, "rb"), what=raw(), n=1e6))
						  ',
				@input_data_1 = N'  
                                 SELECT
                                   *
                                 FROM Automobile_Test',
               @input_data_1_name = N'automobile_test',
			   @output_data_1_name = N'ImgOutput'
			   WITH RESULT SETS ((plot VARBINARY(MAX)))

 
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

/* ---------------------------------------
               Operationalization
----------------------------------------*/

-- Now that we looked at the various options available for in-database analytics
-- how can we implement them in production processes?
-- Let's start by creating a Stored Procedure that returns a prediction based on the model we trained
CREATE PROCEDURE PredictCarPrice
	@wheel_base FLOAT,
	@length FLOAT,
	@width FLOAT,
	@height FLOAT,
	@curb_weight FLOAT,
	@engine_size FLOAT,
	@horsepower FLOAT,
	@predicted_price FLOAT OUTPUT

	AS

		-- Grab the model from our table
		DECLARE @lin_model_raw VARBINARY(MAX) = (SELECT model_object FROM models WHERE model_name = 'automobiles.linmod')

		EXECUTE sp_execute_external_script
			@language = N'R',
            @script = N'

						# Unserialize the model
                        model = rxUnserializeModel(lin_model);
						
						# Load the input parameters into a data frame ans set the correct column names
						automobile_input <- data.frame(cbind(wheel_base_R, length_R, width_R, height_R, curb_weight_R, engine_size_R, horsepower_R))
						colnames(automobile_input) <- c("wheel_base", "length", "width", "height", "curb_weight", "engine_size", "horsepower")

						# Perform the prediction and return the predicted price
						price_prediction_output <- rxPredict(model, data=automobile_input)
						predicted_price_R <- price_prediction_output$price_Pred',
             @params = N'@lin_model varbinary(max),
						 @wheel_base_R FLOAT,
						 @length_R FLOAT,
						 @width_R FLOAT,
						 @height_R FLOAT,
						 @curb_weight_R FLOAT,
						 @engine_size_R FLOAT,
						 @horsepower_R FLOAT,
						 @predicted_price_R FLOAT OUTPUT',
             @lin_model = @lin_model_raw,
			 @wheel_base_R = @wheel_base,
			 @length_R = @length,
			 @width_R = @width,
			 @height_R = @height,
			 @curb_weight_R = @curb_weight,
			 @engine_size_R = @engine_size,
			 @horsepower_R = @horsepower,
			 @predicted_price_R = @predicted_price OUTPUT
		WITH RESULT SETS NONE;

	RETURN
GO

-- Let's test the Stored Procedure with some test data
DECLARE @predicted_output FLOAT

EXEC PredictCarPrice
	@wheel_base = 101.2,
	@length = 176.8,
	@width = 64.8,
	@height = 54.3,
	@curb_weight = 2395,
	@engine_size = 108,
	@horsepower = 110,
	@predicted_price = @predicted_output OUTPUT

SELECT ROUND(@predicted_output,0) AS 'Predicted Car Price' 
 
 -- We can use various methods available in SQL Server to call the SP and do a prediction
 -- For instance, we can create a trigger that performs a prediction and stores it with the inserted data
 -- Let's add a table to hold our data first
CREATE TABLE CarPricePrediction
	(
	[wheel_base] FLOAT,
	[length] FLOAT,
	[width] FLOAT,
	[height] FLOAT,
	[curb_weight] FLOAT,
	[engine_size] FLOAT,
	[horsepower] FLOAT,
	[predicted_price] FLOAT
	)
	
-- Define the trigger
CREATE TRIGGER trgPredictCarPrice ON dbo.CarPricePrediction
INSTEAD OF Insert
	AS
	DECLARE @wheel_base_TR FLOAT
	DECLARE @length_TR FLOAT
	DECLARE @width_TR FLOAT
	DECLARE @height_TR FLOAT
	DECLARE @curb_weight_TR FLOAT
	DECLARE @engine_size_TR FLOAT
	DECLARE @horsepower_TR FLOAT

	SELECT @wheel_base_TR = i.wheel_base FROM inserted i
	SELECT @length_TR = i.[length] FROM inserted i
	SELECT @height_TR = i.height FROM inserted i
	SELECT @width_TR = i.width FROM inserted i
	SELECT @curb_weight_TR = i.curb_weight FROM inserted i
	SELECT @engine_size_TR = i.engine_size FROM inserted i
	SELECT @horsepower_TR = i.horsepower FROM inserted i

	DECLARE @predicted_price FLOAT

	EXEC PredictCarPrice
		@wheel_base = @wheel_base_TR,
		@length = @length_TR,
		@width = @width_TR,
		@height = @height_TR,
		@curb_weight = @curb_weight_TR,
		@engine_size = @engine_size_TR,
		@horsepower = @horsepower_TR,
		@predicted_price = @predicted_price OUTPUT
	
	-- Insert the values we supplied on the INSERT statement together with the
	-- predicted species class we retrieved from the AzureML web service
	INSERT INTO CarPricePrediction (wheel_base, [length], width, height, curb_weight, engine_size, horsepower, predicted_price)
	VALUES (@wheel_base_TR, @length_TR, @width_TR, @height_TR, @curb_weight_TR, @engine_size_TR, @horsepower_TR, ROUND(@predicted_price,2))

-- With the trigger in place, lets insert some data!
-- The trigger should take care of doing the price prediction and adding it with the rest of the data
INSERT INTO CarPricePrediction (wheel_base, [length], width, height, curb_weight, engine_size, horsepower)
VALUES (101.2, 176.8, 64.8, 54.3, 2395, 108, 110)

-- Lets see whats stored
SELECT * FROM CarPricePrediction

-- Cleanup
DROP TABLE Automobile_test
DROP TABLE Automobile_train
DROP TABLE models
DROP PROCEDURE PredictCarPrice
DROP TABLE CarPricePrediction 
