# In-Database Analytics demos

## Traditional Approach.R
This demo shows how to get data from a local SQL Server Instance into an R session, train a Linear Regression model, predict the price of a car and finally, store the results into a table inside SQL Server.

## SQL_InDatabase_Predictions.sql
In this demo we are using the new Machine Learning services available from SQL Server 2016 or greater.
The comments inside the file provide additional information about the requirements.
To use the demos the feature **In-database R Services** (SQL Server 2016) or **In-database Machine Learning Services** (SQL Server 2017 or greater) needs to enable during setup.

## AzureML_From_SQLServer.sql
Inside this demo file we use the In-database services to perform a REST API call towards a web service inside Azure Machine Learning. To use this demo the feature **In-database R Services** (SQL Server 2016) or **In-database Machine Learning Services** (SQL Server 2017 or greater) needs to enable during setup. Also, you will require a predictive experiment inside Azure Machine Learning with a webservice attached to the experiment.
