library(RODBC)
library(dplyr)

# Setup a connection to your SQL Server Instance and get some data
myconn <-odbcDriverConnect('driver={SQL Server};server=localhost;database=automobile;trusted_connection=true')
automobiles <- sqlQuery(myconn, 'SELECT * FROM Automobile')

# Grab a part of the dataset
automobiles_train <- automobiles %>% top_n(120)
automobiles_test <- automobiles %>% top_n(-20)

# We will train a model from the data we selected
# Normally you would store this in a Rdata file for instance
automobiles.linmod <- lm(price ~ wheel_base + length + width + height + curb_weight + engine_size + horsepower, data = automobiles_train)

# Let's predict some stuff we would need to get data from SQL Server that hasn't been 
# scored yet
automobiles_score <- sqlQuery(myconn, 'SELECT TOP 1 * FROM Automobile_Rtest WHERE price = 0')

# Do a prediction on the data that hasn't been scored yet
scored_values <- predict(automobiles.linmod, newdata=automobiles_score)
automobiles_score <- cbind(automobiles_score, scored_values)

# Now we can return the scored data back to SQL through an update
# To make things easier I create a new table
sqlSave(myconn, automobiles_score)


