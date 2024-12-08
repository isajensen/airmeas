library(httr)
library(jsonlite)
library(rvest)
library(dplyr)
library(DBI)
library(RMariaDB)
library(logr)

# skrive i fil
path=Sys.getenv("HOME")
log_open(path,file_name = "airmeas.log")
log_print("Starting")

# forbind database
con <- dbConnect(RMariaDB::MariaDB(), 
                 dbname = "airmeas", 
                 host = "44.220.138.21",
                 user = "dalremote", 
                 password = "Isabella379!")

dbGetQuery(con,"select now()")



log_close()
