-- Create the tabel that will hold our iris predictions
USE [Iris]
GO

CREATE TABLE [dbo].[iris]
	(
	[Sepal_Length] [real] NULL,
	[Sepal_Width] [real] NULL,
	[Petal_Length] [real] NULL,
	[Petal_Width] [real] NULL,
	[Predicted_Species] [varchar](50) NULL
	) 
GO

-- Create the Stored Procedure which will perform a web request
-- against the AzureML webservice we created
-- Make sure to change the API key and Request-Response URL in the R code below
-- Both the RCurl and rjson libraries should be installed in the R installation
-- before running the Stored Procedure
CREATE PROCEDURE [dbo].[sp_Predict_Iris]
	@sepal_length REAL,
	@sepal_width REAL,
	@petal_length REAL,
	@petal_width REAL,
	@predicted_species VARCHAR(50) OUTPUT
AS

	EXEC sp_execute_external_script
		@language= N'R',
		@script = N'
		library("RCurl")
		library("rjson")

			options(RCurlOptions = list(cainfo = system.file("CurlSSL", "cacert.pem", package = "RCurl")))

			h = basicTextGatherer()
			hdr = basicHeaderGatherer()

			req = list(
				Inputs = list(
						"input1"= list(
							list(
									"Sepal_Length" = as.character(sepal_length_R),
									"Sepal_Width" = as.character(sepal_width_R),
									"Petal_Length" = as.character(petal_length_R),
									"Petal_Width" = as.character(petal_width_R)
								)
						)
					),
					GlobalParameters = setNames(fromJSON("{}"), character(0))
			)

			body = enc2utf8(toJSON(req))

			# Copy the API key here
			api_key = "roe3qwvVpDZdyEF+V+DZspjkrZWkqeCFif80Gquujs4CBfEYHUJETBwilAvmzGTUl0durH5LrVfI4VXh6Qy5nQ==" 

			authz_hdr = paste("Bearer", api_key, sep=" ")

			h$reset()

			# Copy the Request-Response URL here
			curlPerform(url = "https://europewest.services.azureml.net/workspaces/d4f5a82a17844022b368e17dbf4b5ebc/services/48216755f3244f678a24314ae0053552/execute?api-version=2.0&format=swagger",
			
			httpheader=c("Content-Type" = "application/json", "Authorization" = authz_hdr),
			postfields=body,
			writefunction = h$update,
			headerfunction = hdr$update,
			verbose = TRUE
			)

			headers = hdr$value()
			result = h$value()
			scored_results <- as.data.frame((fromJSON(result)))

			predicted_species_R <- as.character(scored_results$Scored.Labels)
			',
			@params = N'@sepal_length_R real,
						@sepal_width_R real,
						@petal_length_R real,
						@petal_width_R real,
						@predicted_species_R varchar(50) OUTPUT',
			@sepal_length_R = @sepal_length,
			@sepal_width_R = @sepal_width,
			@petal_length_R = @petal_length,
			@petal_width_R = @petal_width,
			@predicted_species_R = @predicted_species OUTPUT
			WITH RESULT SETS NONE;

RETURN
GO

-- Let's call the Stored Procedure and see what happens!
DECLARE @predicted_output VARCHAR(50)

EXEC sp_Predict_Iris 
		@sepal_length = 5, 
		@sepal_width = 3.2,
		@petal_length = 1.2,
		@petal_width = 0.2,
		@predicted_species = @predicted_output OUTPUT

SELECT @predicted_output
		

-- Create a Instead of Insert Trigger on the iris table
-- This trigger will grab the values of the inserted rows and push them
-- to the Stored Procedure that will perform the classification
CREATE TRIGGER trgPredictSpecies ON dbo.iris
INSTEAD OF Insert
	AS
	DECLARE @sepal_length_TR varchar(50)
	DECLARE @sepal_width_TR varchar(50)
	DECLARE @petal_length_TR varchar(50)
	DECLARE @petal_width_TR varchar(50)

	SELECT @sepal_length_TR = i.Sepal_Length FROM inserted i
	SELECT @sepal_width_TR = i.Sepal_Width FROM inserted i
	SELECT @petal_length_TR = i.Petal_Length FROM inserted i
	SELECT @petal_width_TR = i.Petal_Width FROM inserted i

	DECLARE @predicted_output VARCHAR(50)

	-- Execute the Stored Procedure
	EXEC sp_Predict_Iris 
		@sepal_length = @sepal_length_TR, 
		@sepal_width = @sepal_width_TR,
		@petal_length = @petal_length_TR,
		@petal_width = @petal_width_TR,
		@predicted_species = @predicted_output OUTPUT
	
	-- Insert the values we supplied on the INSERT statement together with the
	-- predicted species class we retrieved from the AzureML web service
	INSERT INTO Iris (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width, Predicted_Species)
	VALUES (@sepal_length_TR, @sepal_width_TR, @petal_length_TR, @petal_width_TR, @predicted_output)

-- Finally we can test everything by inserting a new row
-- The trigger we created grabs the values we supplied and pushes
-- them to the Stored Procedure which in turn sends the parameters to
-- the AzureML webservice. A predicted species is returned and
-- added to the INSERT statement by the trigger
INSERT INTO iris (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width)
VALUES (5,3.2,1.2,0.2)

-- Check the contents of the table
SELECT * FROM iris

-- Another insert, should result in a different species
INSERT INTO iris (Sepal_Length, Sepal_Width, Petal_Length, Petal_Width)
VALUES (5.2,2.7,3.9,1.4)

-- Check the contents of the table
SELECT * FROM iris

-- Cleanup
DROP TABLE Iris
DROP PROCEDURE sp_Predict_Iris
	
