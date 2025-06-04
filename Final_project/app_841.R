library(shiny)
library(shinythemes)
library(shinyjs)
library(dplyr)
library(tidyr)
library(Matrix)
library(proxy)
library(FNN)
library(arules)

# Define UI
ui <- fluidPage(
  theme = shinytheme("cyborg"),
  useShinyjs(),
  
  # Add custom CSS
  tags$head(
    tags$style(HTML("
      body {
        background-image: url('bkgrd.jpeg');
        background-size: cover;
        background-repeat: no-repeat;
        background-attachment: fixed;
      }
      .navbar {
        background-color: #000 !important;
        min-height: 80px !important;
        padding: 10px 0;
      }
      .navbar-brand {
        width: 100%;
        text-align: center;
        position: absolute;
        left: 0;
        margin: 0 !important;
        padding: 0 !important;
      }
      .navbar-brand img {
        height: 70px !important;
        display: inline-block;
        vertical-align: middle;
      }
      .input-box {
        width: 100%;
        height: 300px;
        padding: 15px;
        border: 1px solid #ccc;
        border-radius: 4px;
        resize: none;
        background-color: rgba(255, 255, 255, 0.9);
        font-size: 16px;
        line-height: 1.5;
        font-family: monospace;
      }
      .logic-input-box {
        width: 100%;
        height: 100px;
        padding: 15px;
        border: 1px solid #ccc;
        border-radius: 4px;
        resize: none;
        background-color: rgba(255, 255, 255, 0.9);
        font-size: 16px;
        line-height: 1.5;
        font-family: monospace;
        margin-top: 20px;
      }
      .logic-result-box {
        width: 100px;
        height: 40px;
        padding: 8px;
        border: 1px solid #ccc;
        border-radius: 4px;
        background-color: rgba(255, 255, 255, 0.9);
        font-size: 18px;
        text-align: center;
        margin: 20px auto;
        font-weight: bold;
      }
      .output-box {
        background-color: rgba(255, 255, 255, 0.9);
        padding: 20px;
        border-radius: 4px;
        min-height: 300px;
        max-height: 500px;
        overflow-y: auto;
        word-wrap: break-word;
        font-size: 16px;
      }
      .movie-item {
        margin: 8px 0;
        padding: 12px;
        background-color: rgba(0, 0, 0, 0.1);
        border-radius: 4px;
        font-size: 16px;
      }
      .predict-button {
        margin-top: 25px;
        padding: 12px 35px;
        font-size: 20px;
        background-color: #007bff;
        color: white;
        border: none;
        border-radius: 5px;
        transition: background-color 0.3s;
      }
      .predict-button:hover {
        background-color: #0056b3;
      }
      .container-wrapper {
        background-color: rgba(0, 0, 0, 0.7);
        padding: 30px;
        border-radius: 8px;
        margin-top: 30px;
      }
      .logic-section {
        margin-top: 30px;
        text-align: center;
      }
      .logic-label {
        color: white;
        font-size: 18px;
        margin-bottom: 10px;
      }
    "))
  ),
  
  navbarPage(
    title = div(style="width: 100%; text-align: center;", img(src = "dmlogo.jpeg", height = "70px")),
    id = "nav",
    tabPanel("",
             div(class = "container-wrapper",
                 fluidRow(
                   column(
                     6,
                     h2("Input", style = "color: white; margin-bottom: 20px;"),
                     tags$textarea(
                       id = "input_row",
                       class = "input-box",
                       placeholder = "Enter movies in the following format:\n['The Dark Knight', 'Inception', 'The Matrix', 'Pulp Fiction', 'Fight Club']"
                     )
                   ),
                   column(
                     6,
                     h2("Recommendations", style = "color: white; margin-bottom: 20px;"),
                     div(
                       class = "output-box",
                       uiOutput("output_grid")
                     )
                   )
                 ),
                 div(
                   style = "text-align: center;",
                   actionButton("predict_btn", "Get Recommendations", class = "predict-button")
                 ),
                 # New Logic Section
                 div(class = "logic-section",
                     div(class = "logic-label"),
                     tags$textarea(
                       id = "logic_input",
                       class = "logic-input-box",
                       placeholder = "Enter your logic here..."
                     ),
                     div(class = "logic-result-box",
                         textOutput("logic_result")
                     )
                 )
             )
    )
  )
)

# Define Server Logic
server <- function(input, output, session) {
  # Debug logs
  cat("Server initialized.\n")
  
  # Load libraries
  cat("Loading libraries...\n")
  
  # Load the dataset and preprocess (run this once when the app starts)
  cat("Loading data...\n")
  new_df <- tryCatch({
    read.csv("final_df.csv")
  }, error = function(e) {
    stop("Error loading final_df.csv: ", e$message)
  })
  cat("Data loaded successfully.\n")
  
  # Preprocess dataset
  tryCatch({
    movie_rating_counts <- new_df %>%
      group_by(title) %>%
      summarize(count_of_no_of_ratings_for_that_movie = n())
    
    popular_movies <- movie_rating_counts %>%
      filter(count_of_no_of_ratings_for_that_movie > 1100) %>%
      pull(title)
    
    popular_movies_new_df <- new_df %>%
      filter(title %in% popular_movies) %>%
      group_by(title, userId) %>%
      summarize(rating = mean(rating, na.rm = TRUE), .groups = "drop")
    
    movie_features_df <- popular_movies_new_df %>%
      pivot_wider(names_from = userId, values_from = rating, values_fill = 0)
    
    movie_features_matrix <- as.matrix(movie_features_df[-1])
    rownames(movie_features_matrix) <- movie_features_df$title
    
    movie_features_sparse <- Matrix(movie_features_matrix, sparse = TRUE)
    
    # Cosine similarity matrix
    cosine_similarity <- function(x) {
      sim <- tcrossprod(x) / (sqrt(rowSums(x^2) %*% t(rowSums(x^2))))
      return(sim)
    }
    similarity_matrix <- cosine_similarity(movie_features_sparse)
    
    # KNN model
    find_knn <- function(similarity_matrix, k) {
      apply(similarity_matrix, 1, function(row) {
        order(row, decreasing = TRUE)[2:(k + 1)]  # Exclude self
      })
    }
    model_knn <- find_knn(similarity_matrix, k = 6)
    
    # Prepare transaction data for ARM
    transaction_data <- popular_movies_new_df %>%
      filter(rating > 3) %>%
      group_by(userId) %>%
      summarize(movies = list(title)) %>%
      pull(movies)
    
    transactions <- as(transaction_data, "transactions")
    association_rules <- apriori(transactions, parameter = list(supp = 0.01, conf = 0.5, target = "rules"))
    
    cat("Data preprocessing complete.\n")
  }, error = function(e) {
    stop("Error during data preprocessing: ", e$message)
  })
  
  # Logic Input Observer
  observe({
    logic_text <- input$logic_input
    # Placeholder for logic processing
    # You can add your logic (A) processing here
    # For now, just displaying a sample number
    output$logic_result <- renderText({
      if (nchar(logic_text) > 0) {
        "42" # Replace with actual logic result
      } else {
        ""
      }
    })
  })
  
  # Predict button logic
  observeEvent(input$predict_btn, {
    # Get user input and parse it
    input_text <- input$input_row
    # Remove square brackets and split by commas
    input_text <- gsub("^\\[|\\]$", "", input_text)
    # Extract movies between single quotes
    input_movies <- gregexpr("'([^']*)'", input_text, perl=TRUE)
    input_movies <- regmatches(input_text, input_movies)[[1]]
    # Remove the surrounding quotes
    input_movies <- gsub("^'|'$", "", input_movies)
    input_movies <- trimws(input_movies)
    
    # Validate input movies
    valid_input_movies <- input_movies[input_movies %in% rownames(movie_features_sparse)]
    
    if (length(valid_input_movies) == 0) {
      output$output_grid <- renderUI({
        div(class = "alert alert-danger",
            "No valid movies found in the dataset! Please check your movie titles and try again."
        )
      })
      return()
    }
    
    # Aggregate features for input movies
    if (length(valid_input_movies) == 1) {
      input_aggregated_vector <- movie_features_matrix[valid_input_movies, ]
    } else {
      input_aggregated_vector <- colMeans(movie_features_matrix[valid_input_movies, , drop = FALSE])
    }
    input_similarity <- as.vector(movie_features_matrix %*% input_aggregated_vector) / 
      (sqrt(rowSums(movie_features_matrix^2)) * sqrt(sum(input_aggregated_vector^2)))
    
    # Get KNN recommendations
    knn_recommendations_indices <- order(input_similarity, decreasing = TRUE)[1:400]
    knn_recommendations <- rownames(movie_features_matrix)[knn_recommendations_indices]
    
    # ARM recommendations
    get_association_recommendations <- function(input_movies, rules, top_n = 5) {
      movie_rules <- subset(rules, lhs %pin% input_movies)
      if (length(movie_rules) == 0) return(NULL)
      sorted_rules <- sort(movie_rules, by = "confidence", decreasing = TRUE)
      recommendations <- unique(as.character(rhs(sorted_rules)))
      return(recommendations[1:top_n])
    }
    arm_recommendations <- get_association_recommendations(valid_input_movies, association_rules)
    
    # Combine recommendations
    combined_recommendations <- unique(c(knn_recommendations, arm_recommendations))
    final_recommendations <- combined_recommendations[!(combined_recommendations %in% input_movies)]
    
    # Render final recommendations
    output$output_grid <- renderUI({
      if (length(final_recommendations) == 0) {
        div(class = "alert alert-warning", "No recommendations found.")
      } else {
        tagList(
          div(class = "alert alert-success", "Based on your input, here are your movie recommendations:"),
          lapply(final_recommendations[1:10], function(movie) {
            div(class = "movie-item", 
                tags$span(class = "movie-title", movie)
            )
          })
        )
      }
    })
  })
}

# Combine UI and Server into Shiny App
shinyApp(ui = ui, server = server)