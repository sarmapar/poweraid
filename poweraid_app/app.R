##test

# Install required packages
required_packages <- c("shiny", "shinyWidgets", "shinycssloaders",
                       "plotly", "dplyr", "tidyr", "mgcv")

new_packages <- required_packages[!(required_packages %in% installed.packages()[,"Package"])]
if(length(new_packages))
  install.packages(new_packages, dependencies = T)

if (!require("RNASeqPower", quietly = TRUE)){
  if (!require("BiocManager", quietly = TRUE))
    install.packages("BiocManager", dependencies = T)

  BiocManager::install("RNASeqPower", dependencies = T)
}


# Load required packages
library(shiny)
library(shinyWidgets)
library(shinycssloaders)
library(plotly)
library(dplyr)
library(tidyr)
library(RNASeqPower)

#Set min and max values
dispMin <- 0.001
dispMax <- 0.1
repMin <- 2
repMax <- 10
fcMin <- 1.1
fcMax <- 10

# load data
load("../data/appPowerPerc.rda")
load("../data/hicObExRao.rda")

# filter and clean data
hpowPowPerc$seqDepth <- sub("M","",hpowPowPerc$seqDepth)
hpowPowPerc$seqDepth <- sub("B","000",hpowPowPerc$seqDepth)
hpowLines <- hpowPowPerc %>%
  mutate(total = as.numeric(seqDepth)*as.numeric(replicates)) %>%
  group_by(total)

totSeqDepths <- as.numeric(unique(hpowLines$total))

dispVals <- unique(hpowPowPerc$disp)
seqDepths <- c("50M","100M","250M","500M","750M","1B","2B","3B","4B","5B")

## prepare data for power calculations
# helper functions
calcSigFC <- function(obs, exp, fc){
  return(((obs-exp)*fc + exp) / obs)
}

# filter and clean data
hicExpLong <- hicObExRao %>%
  dplyr::select(ends_with("exp")) %>%
  pivot_longer(cols = everything(),
               names_to = "seqDepth",
               values_to = "exp",
               names_pattern = "rao_(.*)_exp")

hpowAll <- hicObExRao %>%
  dplyr::select(ends_with("obs"), distance) %>%
  pivot_longer(cols = !distance,
               names_to = "seqDepth",
               values_to = "obs",
               names_pattern = "rao_(.*)_obs")

hpowAll["exp"] <-cbind(hicExpLong$exp)

hpowAll$seqDepth <- sub("M","",hpowAll$seqDepth)
hpowAll$seqDepth <- sub("B","000",hpowAll$seqDepth)

hpowAll <- hpowAll %>%
  dplyr::filter(distance <= 2000000) %>%
  dplyr::filter(obs >= exp)

# Define UI
ui <- fluidPage(

    # Application title
    titlePanel("Hi-C Poweraid: Determining the Power to Call Differential Loops"),


    # Sidebars for Tab panels
    tabsetPanel(
      tabPanel("Power across Sequencing Depth", fluid = T,
        sidebarLayout(
          sidebarPanel(
            shinyWidgets::pickerInput(inputId = "disp",
                                      label = "Dispersion",
                                      choices = unique(hpowLines$dispersion),
                                      multiple = T,
                                      inline = T,
                                      selected = 0.001),

            radioButtons(inputId = "powerThresh",
                         label = "Power Threshold",
                         choiceNames = c(">0.8", ">0.9"),
                         choiceValues = c("percAbove80","percAbove90")),

            shinyWidgets::sliderTextInput(inputId = "repRange",
                        label = "Replicates per Condion",
                        choices = unique(sort(hpowLines$replicates)),
                        selected = c(min(hpowLines$replicates),max(hpowLines$replicates)),
                        grid = T)),
        mainPanel(
          plotlyOutput("dispPlotly"),
          uiOutput("dynamic")))),

      tabPanel("Power across Loop Sizes", fluid = T,
        sidebarLayout(
          sidebarPanel(
            shinyWidgets::pickerInput(inputId = "sd",
                                      label = "Sequencing Depth per Replicate (Contacts, in billions)",
                                      choices = as.numeric(unique(hpowLines$seqDepth))/1000,
                                      multiple = F,
                                      inline = T,
                                      selected = 1),

            sliderInput(inputId = "reps",
                        label = "Replicates per Condition",
                        value = 2,
                        min = repMin,
                        max = repMax,
                        step = 1),

            htmlOutput("totalSD"),

            sliderInput(inputId = "disp2",
                          label = "Dispersion",
                          value = 0.001,
                          min = dispMin,
                          max = dispMax,
                          step = 0.001),

            sliderInput(inputId = "fc",
                         label = "Fold Change",
                         value = 2,
                         min = fcMin,
                         max = fcMax,
                         step = 0.1),

            radioButtons(inputId = "powerThreshDist",
                         label = "Power Threshold",
                         choiceNames = c(">0.8", ">0.9"),
                         choiceValues = c("percAbove80","percAbove90")),

            actionButton("gobutton","Go")),

        mainPanel(
          plotlyOutput("distancePlots") %>% withSpinner(type = 1, color = "#1c8ccf"),
          htmlOutput("percentageSummary") %>% withSpinner(type = 0))))
    )
)

# Define server logic
server <- function(input, output, session) {

  global <- reactiveValues(percAboveThreshTot = NULL,
                           powerThreshDist = NULL)

  #### Tab 1: Dispersion and power
    output$dispPlotly <- renderPlotly({

      #filter for replicates and total seq depth
      hpowLinesFiltered <- hpowLines %>%
        filter(replicates >= input$repRange[1],
               replicates <= input$repRange[2],
               dispersion %in% input$disp)

     #plotly plot for dispersions
      fig <- plot_ly(group_by(hpowLinesFiltered, replicates),
                     type = 'scatter', mode = "lines",
                     x = ~total/1000, y =~(eval(sym(input$powerThresh))),
                     color = ~as.factor(dispersion),
                     text = ~paste0("<i>Dispersion</i>: ", dispersion,
                                    '<br><i>Replicates</i>: ', replicates),
                     hovertemplate = paste('%{text}',
                                           '<br><i>Total seq depth</i>: %{x} billion contacts',
                                           '<br><b>% Well-powered Loops: </b>%{y:.2f}%',
                                           '<extra></extra>')) %>%
        layout(legend=list(title=list(text='Dispersion'))) %>%
        group_by(replicates) %>%
        layout(xaxis = list(title = 'Total Sequencing Depth per Condition (Contacts, in billions)'),
               yaxis = list(title = 'Percent of Well-powered Loops'))

    fig

    })

    #### Tab 2: Distance-dependence

    ## Total sequencing depth for slider inputs
    output$totalSD <- renderText({paste0("<b>Total sequencing depth: </b>", as.numeric(input$sd)*as.numeric(input$reps),
                                         " billion contacts per condition<br><br>")})


    ## prepare data table for current condition
    reactiveData <- eventReactive(input$gobutton,{

      ##Calculate power
      hpowPercByDistData <- hpowAll %>%
        filter(seqDepth == as.numeric(input$sd)*1000)  %>%
        dplyr::mutate(
          loopSigFC = input$fc,
          obsSigFC = calcSigFC(obs, exp, input$fc))

      totLoops <- nrow(hpowPercByDistData)

      power <- vector()
      for(row in 1:nrow(hpowPercByDistData)){
        if(is.na(hpowPercByDistData$obsSigFC[row]) | hpowPercByDistData$obsSigFC[row] == 0){
          power[row] <- 0
        } else {
          power[row] <- rnapower(alpha=0.05/totLoops,
                                 cv = sqrt(as.numeric(input$disp2)),
                                 depth = hpowPercByDistData$obs[row],
                                 effect = hpowPercByDistData$obsSigFC[row],
                                 n = as.numeric(input$reps))
        }
      }

      hpowPercByDistData$power <- power

      # calculate percent of well-powered loops
      if(input$powerThreshDist == "percAbove80"){
        global$powerThreshDist <- filter(hpowPercByDistData,power >= 0.8)
        global$percAboveThreshTot <- round((sum(hpowPercByDistData$power >= 0.8)/nrow(hpowPercByDistData))*100,2)
      } else {
        global$powerThreshDist <- filter(hpowPercByDistData,power >= 0.9)
        global$percAboveThreshTot <- round((sum(hpowPercByDistData$power >= 0.9)/nrow(hpowPercByDistData))*100,2)
      }

      # generate best fit gam model
      hpowPowPercByDist <- hpowPercByDistData %>%
        dplyr::group_by(distance) %>%
        dplyr::summarize(percAbove80 = (sum(power >= 0.8)/dplyr::n())*100,
                         percAbove90 = (sum(power >= 0.9)/dplyr::n())*100,
                         distance = distance,
                         loopSigFC = loopSigFC) %>%
        arrange(distance) %>%
        ungroup()

      if(input$powerThreshDist == "percAbove80"){
        gam <- mgcv::gam(percAbove80 ~ s(distance), data = hpowPowPercByDist) }
      else{
        gam <- mgcv::gam(percAbove90 ~ s(distance), data = hpowPowPercByDist)
      }

      #return data
      reactiveData <- list(hpowPercByDistData = hpowPercByDistData,
                           hpowPowPercByDist = hpowPowPercByDist,
                           gam = gam,
                           powerThreshDist = input$powerThreshDist)

    }, ignoreNULL = F)

    output$distancePlots <- renderPlotly({

      #### Making first plot

      hist <- plot_ly() %>%
        add_histogram(x = ~reactiveData()$hpowPercByDistData$distance,
                      name = "All Loops",
                      marker = list(color = "lightgrey"),
                      nbinsx = 100) %>%
        add_histogram(x = ~global$powerThreshDist$distance,
                      name = "Well-powered\nLoops",
                      marker = list(color = "forestgreen"),
                      nbinsx = 100) %>%
        layout(barmode="overlay",
               xaxis = list(title = "distance (bases)"),
               yaxis = list(title = "# of loops"),
               title = "Well-powered loops by distance")

      #### Making second plot

      fig <- plot_ly(reactiveData()$hpowPowPercByDist, x = ~distance, y = ~(eval(sym(reactiveData()$powerThreshDist))),
                     type = 'scatter', mode = 'lines', name = "raw data", line = list(color = "lightgray")) %>%
        add_trace(y = predict(reactiveData()$gam), type = 'scatter', mode = 'lines', name = "smooth fit", line = list(color = "#288BA8")) %>%
        layout(yaxis = list(title = '% of well-powered\nloops',  range = list(0, 100)))


      distancePlots <- subplot(fig, hist, nrows = 2, shareX = TRUE, titleY = TRUE, margin = 0.075) %>%
        layout(hovermode = "x unified")

      distancePlots

      })

    output$percentageSummary <- eventReactive(global$percAboveThreshTot, {
      if(!is.null(global$percAboveThreshTot & !is.na(global$percAboveThreshTot))){
        paste0("<br><b>Results</b><br>",global$percAboveThreshTot,
               "% of all loops have a power above ", sub("percAbove",".",input$powerThreshDist),
               " to detect a ", input$fc, "-fold change when <br>",
               "<b> Sequencing Depth per Replicate </b> = ", input$sd, " billion contacts <br>",
               "<b> Dispersion </b> = ", input$disp2, "<br>",
               "<b> Replicates per Condition </b> = ", input$reps)
      }
    })
}

# Run the application
shinyApp(ui = ui, server = server)


