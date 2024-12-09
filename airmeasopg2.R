library(httr)
library(jsonlite)
library(rvest)
library(dplyr)
library(DBI)
library(RMariaDB)
library(logr)
library(logger)

# Logfil-konfiguration
log_file_path <- "~/git/airmeas/airmeas/airmeas.log"
log_open(log_file_path)
log_print("Script starting")

# Opret forbindelse til db
log_print("Establishing database connection")
con <- dbConnect(RMariaDB::MariaDB(), 
                 dbname = "airmeas", 
                 host = "44.220.138.21",
                 user = "dalremote", 
                 password = "__________")
log_print("Database connection established")

# Stationer og URL'er
stations <- list(
  list(name = "Anholt", 
       url = "https://envs2.au.dk/Luftdata/Presentation/table/Rural/ANHO", 
       js_url = "https://envs2.au.dk/Luftdata/Presentation/table/MainTable/Rural/ANHO", 
       table_name = "anholt"),
  
  list(name = "HCAB", 
       url = "https://envs2.au.dk/Luftdata/Presentation/table/Copenhagen/HCAB", 
       js_url = "https://envs2.au.dk/Luftdata/Presentation/table/MainTable/Copenhagen/HCAB", 
       table_name = "hcab"),
  
  list(name = "Risø", 
       url = "https://envs2.au.dk/Luftdata/Presentation/table/Rural/RISOE", 
       js_url = "https://envs2.au.dk/Luftdata/Presentation/table/MainTable/Rural/RISOE", 
       table_name = "risoe"),
  
  list(name = "Aarhus", 
       url = "https://envs2.au.dk/Luftdata/Presentation/table/Aarhus/AARH3", 
       js_url = "https://envs2.au.dk/Luftdata/Presentation/table/MainTable/Aarhus/AARH3", 
       table_name = "aarhus")
)

# Funktion til at hente miljødata
fetch_miljødata <- function(station_url, js_url) {
  tryCatch({
    raw_res <- GET(url = station_url, add_headers(`User-Agent` = "Mozilla/5.0"))
    raw_content <- content(raw_res, as = "text", encoding = "UTF-8")
    token <- read_html(raw_content) %>% html_element("input[name='__RequestVerificationToken']") %>% html_attr("value")
    
    post_res <- POST(url = js_url, 
                     add_headers(`User-Agent` = "Mozilla/5.0"),
                     body = list(`__RequestVerificationToken` = token), 
                     encode = "form")
    
    table_html <- content(post_res, as = "text", encoding = "UTF-8")
    table_page <- read_html(table_html)
    
    rows <- table_page %>% html_elements("tr")
    table_data <- rows %>% html_elements("td") %>% html_text(trim = TRUE)
    header <- table_page %>% html_elements("th") %>% html_text(trim = TRUE)
    
    header_amount <- length(header)
    table_matrix <- matrix(data = unlist(table_data), ncol = header_amount, byrow = TRUE)
    df <- as.data.frame(table_matrix)
    colnames(df) <- header
    
    df[, 2:header_amount] <- lapply(df[, 2:header_amount], function(x) as.numeric(gsub(",", ".", x)))
    df$scrapedate <- Sys.time()
    
    if ("PM2.5" %in% colnames(df)) {
      colnames(df)[which(colnames(df) == "PM2.5")] <- "PM2_5"
    }
    
    return(df)
  }, error = function(e) {
    log_error(paste("Failed to fetch data:", e$message))
    return(NULL)
  })
}

# Loop gennem stationerne og behandl data
for (station in stations) {
  log_print(paste("Fetching data for station:", station$name))
  df <- fetch_miljødata(station$url, station$js_url)
  
  if (is.null(df)) {
    log_print(paste("No data returned for station:", station$name))
    next
  }
  
  df$`Målt (starttid)` <- as.POSIXct(df$`Målt (starttid)`, format = "%d-%m-%Y %H:%M", tz = "UTC")
  
  tryCatch({
    dbExecute(con, paste0("DELETE FROM ", station$table_name, " WHERE 1=1"))
    dbWriteTable(con, station$table_name, df, append = TRUE, row.names = FALSE)
    log_print(paste("Data added for station:", station$name))
  }, error = function(e) {
    log_error(paste("Database operation failed for station:", station$name, "-", e$message))
  })
}

log_print("Closing database connection")
dbDisconnect(con)
log_print("Script finished")
log_close()
