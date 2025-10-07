/**
* Name: daily_result
* Based on the internal empty template. 
* Author: pc
* Tags: 
* 
* This model visualizes res file (daily result output from ORYZA)
*/

model daily_result

global {
    file plot_shp <- file("../includes/Shapefile/kiengiang.shp");
    geometry shape <- envelope(plot_shp); 
    
    // Scenarios
    list<string> SCENARIOS <- ["Baseline", "Increase 5°C", "Increase AWD Threshold"];

    // Season options
    list<int> SEASON_OPTIONS <- [1,2,3,4,5,6,7,8,9,10];
    map<int, string> SEASON_LABELS <- [
        1::"Winter-Spring 2015-2016",
        2::"Summer-Autumn 2016",
        3::"Winter-Spring 2016-2017",
        4::"Summer-Autumn 2017",
        5::"Winter-Spring 2017-2018",
        6::"Summer-Autumn 2018",
        7::"Winter-Spring 2018-2019",
        8::"Summer-Autumn 2019",
        9::"Winter-Spring 2019-2020",
        10::"Summer-Autumn 2020"
    ];
    
    string scenario_1 <- "Baseline";
    string scenario_2 <- "Increase 5°C";
    int selected_season <- 1;
    
    string REGIME_CF <- "CF";
    string REGIME_AWD <- "AWD";
    
    // store the data[scenario_regime_season_day_variable][value]
    map<string, float> data;
    
    // current season info
    int current_season_index <- 1;
    list<int> days_in_season;
    int current_day_index <- 0;
    int current_day <- 1;
    bool season_complete <- false;
    
    float max_water_level <- 100.0;
    
    map<string, list<int>> regime_plots <- [
        REGIME_CF::[2,4,5],
        REGIME_AWD::[1,3]
    ];
    
    init {
        create plot from: plot_shp with: [plot_id::int(read("PLOT_ID"))];
        write "Loading data...";
        do load_data;
        do set_current_season(selected_season);
        do assign_plot_regimes;
    }

    action load_data {
        do load_csv_data("Baseline", "CF", "../includes/Results/CF_s1/cf_res.csv");
        do load_csv_data("Baseline", "AWD", "../includes/Results/AWD_s1/awd_res.csv");
        do load_csv_data("Increase 5°C", "CF", "../includes/Results/CF_s2/cf_res.csv");
        do load_csv_data("Increase 5°C", "AWD", "../includes/Results/AWD_s2/awd_res.csv");
        do load_csv_data("Increase AWD Threshold", "CF", "../includes/Results/CF_s3/cf_res.csv");
        do load_csv_data("Increase AWD Threshold", "AWD", "../includes/Results/AWD_s3/awd_res.csv");
    }
    
    action load_csv_data(string scenario, string regime, string filepath) {
        file data_file <- csv_file(filepath);
        matrix<string> csv_matrix <- matrix(data_file);
        list<string> headers <- data_file.attributes;
        
        // column index
        int col_season <- headers index_of "RERUN_SET";
        int col_day <- headers index_of "DOY";
        int col_wl <- headers index_of "WL0";
        int col_lai <- headers index_of "LAI";
        int col_soc <- headers index_of "SOC";
        int col_son <- headers index_of "SON";
        int col_nh3 <- headers index_of "NH3";
        int col_n2on <- headers index_of "N2ON";
        int col_co2c <- headers index_of "CO2C";
        int col_ch4c <- headers index_of "CH4C";
        int col_tmax <- headers index_of "TMAX";
        int col_tmin <- headers index_of "TMIN";
        
        // read each row and store with key
        loop i from: 0 to: csv_matrix.rows - 1 {
            int season <- int(csv_matrix[col_season, i]);
            int day <- int(csv_matrix[col_day, i]);
            
            // create base key
            string base_key <- scenario + "_" + regime + "_" + season + "_" + day;
            
            // key points to variables
            data[base_key + "_water_level"] <- float(csv_matrix[col_wl, i]);
            data[base_key + "_lai"] <- float(csv_matrix[col_lai, i]);
            data[base_key + "_soc"] <- float(csv_matrix[col_soc, i]);
            data[base_key + "_son"] <- float(csv_matrix[col_son, i]);
            data[base_key + "_nh3"] <- float(csv_matrix[col_nh3, i]);
            data[base_key + "_n2on"] <- float(csv_matrix[col_n2on, i]);
            data[base_key + "_co2c"] <- float(csv_matrix[col_co2c, i]);
            data[base_key + "_ch4c"] <- float(csv_matrix[col_ch4c, i]);
            
            // calculate daily mean temp based on min/max temp
            float daily_mean_temp <- (float(csv_matrix[col_tmax, i]) + float(csv_matrix[col_tmin, i])) / 2.0;
            data[base_key + "_temperature"] <- daily_mean_temp;
        }
        
        write "Loaded " + scenario + " " + regime + " data";
    }
    
    // get value of variable using string key
    float get_value(string scenario, string regime, string variable, int season, int day) {
        string key <- scenario + "_" + regime + "_" + season + "_" + day + "_" + variable;
        
        if (data contains_key key) {
            return data[key];
        }
        return 0.0;
    }

    action set_current_season(int season_index) {
        current_season_index <- season_index;
        season_complete <- false;
        days_in_season <- [];
        
        loop d from: 1 to: 365 {
            string key <- scenario_1 + "_" + REGIME_CF + "_" + season_index + "_" + d + "_water_level";
            if (data contains_key key) {
                days_in_season <- days_in_season + d;
            }
        }
        
        current_day_index <- 0;
        write "Loaded " + SEASON_LABELS[season_index] + " with " + length(days_in_season) + " days";
    }
    
    action assign_plot_regimes {
        ask plot {
            regime <- "None";
            water_level_s1 <- 0.0;
            water_level_s2 <- 0.0;
            
            loop regime_name over: regime_plots.keys {
                if (regime_plots[regime_name] contains plot_id) {
                    regime <- regime_name;
                    break;
                }
            }
        }
    }
    
    reflex update_simulation when: current_day_index < length(days_in_season) and !season_complete {
        current_day <- days_in_season[current_day_index];
        ask plot {
            if (regime != "None") {
                water_level_s1 <- min([max([world.get_value(scenario_1, regime, "water_level", current_season_index, current_day), 0.0]), max_water_level]);
                water_level_s2 <- min([max([world.get_value(scenario_2, regime, "water_level", current_season_index, current_day), 0.0]), max_water_level]);
            }
        }
        
        current_day_index <- current_day_index + 1;
        
        if (current_day_index >= length(days_in_season)) {
            season_complete <- true;
            do pause;
            write "Season complete.";
        }
    }
}

species plot {
    int plot_id;
    string regime;
    float water_level_s1 <- 0.0;
    float water_level_s2 <- 0.0;
    
    aspect scenario_1 {
        rgb plot_color <- calculate_water_color_s1();
        draw shape color: plot_color border: #black width: 2;
        draw string(regime);
        
        draw string("Water level: " + water_level_s1 with_precision 1 + "mm")
            color: #white size: 10 at: {location.x, location.y - 8};
    }
    
    aspect scenario_2 {
        rgb plot_color <- calculate_water_color_s2();
        draw shape color: plot_color border: #black width: 2;
        draw string(regime);
        
        draw string("Water level: " + water_level_s2 with_precision 1 + "mm")
            color: #white size: 10 at: {location.x, location.y -8};
    }
    
    rgb calculate_water_color_s1 {
        if (water_level_s1 <= 0.0) {
            return rgb(139, 119, 101);
        } else {
            float water_ratio <- water_level_s1 / max_water_level;
            int blue_intensity <- int(255 - (water_ratio * 205));
            blue_intensity <- max([50, min([255, blue_intensity])]);
            int green_component <- int(blue_intensity * 0.3);
            return rgb(0, green_component, blue_intensity);
        }
    }
    
    rgb calculate_water_color_s2 {
        if (water_level_s2 <= 0.0) {
            return rgb(139, 119, 101);
        } else {
            float water_ratio <- water_level_s2 / max_water_level;
            int blue_intensity <- int(255 - (water_ratio * 205));
            blue_intensity <- max([50, min([255, blue_intensity])]);
            int green_component <- int(blue_intensity * 0.3);
            return rgb(0, green_component, blue_intensity);
        }
    }
}

experiment water_level type: gui {
    float minimum_cycle_duration <- 0.1#s;
    
    parameter "Scenario 1" var: scenario_1 category: "Scenario Selection" among: SCENARIOS;
    parameter "Scenario 2" var: scenario_2 category: "Scenario Selection" among: SCENARIOS;
    parameter "Select Season" var: selected_season category: "Season Selection" among: SEASON_OPTIONS;
    
    output synchronized: false {
        layout vertical([
            horizontal([0::5000, 1::5000])::5000,
            horizontal([2::5000, 3::5000])::5000
        ])
        
        editors: false toolbars: false;
        
        display scenario_1 type: 2d {
            species plot aspect: scenario_1;
        }
        
        display scenario_2 type: 2d {
            species plot aspect: scenario_2;
        }
        
        display "Water Level/Temperature" type: 2d {
            chart "" type: series background: #white 
                y_label: "Water level (mm)" y2_label: "Temperature (°C)" {
                
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "water_level", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "water_level", current_season_index, current_day)
                    color: #red marker: false style: line;
                
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "water_level", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "water_level", current_season_index, current_day)
                    color: #darkred marker: false style: line;
                
                data (scenario_1 + " Temp") 
                    value: get_value(scenario_1, REGIME_CF, "temperature", current_season_index, current_day)
                    use_second_y_axis: true color: #chartreuse marker: false style: step;
                data (scenario_2 + " Temp") 
                    value: get_value(scenario_2, REGIME_AWD, "temperature", current_season_index, current_day)
                    use_second_y_axis: true color: #orange marker: false style: step;
            }
        }
        
        display "LAI Comparison" type: 2d {
            chart "Leaf Area Index" type: series background: #white {
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "lai", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "lai", current_season_index, current_day)
                    color: #red marker: false style: line;
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "lai", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "lai", current_season_index, current_day)
                    color: #darkred marker: false style: line;
            }
        }
    }
}

 
experiment emission type: gui {
    float minimum_cycle_duration <- 0.1#s;
    
    parameter "Scenario 1" var: scenario_1 category: "Scenario Selection" among: SCENARIOS;
    parameter "Scenario 2" var: scenario_2 category: "Scenario Selection" among: SCENARIOS;
    parameter "Select Season" var: selected_season category: "Season Selection" among: SEASON_OPTIONS;

    output synchronized: false {
        layout vertical([
            horizontal([0::5000, 1::5000])::5000,
            horizontal([2::5000, 3::5000])::5000
        ])
        editors: false toolbars: false;

        display "N2O Comparison" type: 2d {
            chart "Nitrous Oxide" type: series background: #white
            y_label: "N2O Level (per ha)" {
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "n2on", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "n2on", current_season_index, current_day)
                    color: #red marker: false style: line;
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "n2on", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "n2on", current_season_index, current_day)
                    color: #darkred marker: false style: line;
            }
        }

        display "SOC Comparison" type: 2d {
            chart "Soil Organic Carbon" type: series background: #white
            y_label: "SOC Level (per ha)" {
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "soc", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "soc", current_season_index, current_day)
                    color: #red marker: false style: line;
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "soc", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "soc", current_season_index, current_day)
                    color: #darkred marker: false style: line;
            }
        }

        display "CO2 Comparison" type: 2d {
            chart "CO2" type: series background: #white
            y_label: "CO2 (per ha)" {
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "co2c", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "co2c", current_season_index, current_day)
                    color: #red marker: false style: line;
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "co2c", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "co2c", current_season_index, current_day)
                    color: #darkred marker: false style: line;
            }
        }

        display "CH4 Comparison" type: 2d {
            chart "CH4" type: series background: #white
            y_label: "CH4 (per ha)" {
                data (scenario_1 + " CF") 
                    value: get_value(scenario_1, REGIME_CF, "ch4c", current_season_index, current_day)
                    color: #blue marker: false style: line;
                data (scenario_1 + " AWD") 
                    value: get_value(scenario_1, REGIME_AWD, "ch4c", current_season_index, current_day)
                    color: #red marker: false style: line;
                data (scenario_2 + " CF") 
                    value: get_value(scenario_2, REGIME_CF, "ch4c", current_season_index, current_day)
                    color: #darkblue marker: false style: line;
                data (scenario_2 + " AWD") 
                    value: get_value(scenario_2, REGIME_AWD, "ch4c", current_season_index, current_day)
                    color: #darkred marker: false style: line;
            }
        }
    }
}
