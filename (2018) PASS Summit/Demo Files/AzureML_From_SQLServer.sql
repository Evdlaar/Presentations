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


-- Cleanup
DROP TABLE Iris
DROP PROCEDURE sp_Predict_Iris
	
