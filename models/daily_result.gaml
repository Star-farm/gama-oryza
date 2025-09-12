/**
* Name: dailyresult
* Based on the internal empty template. 
* Author: pc
* Tags: 
*/

model daily_result

global {
    file plot_shp <- file("../includes/Shapefile/kiengiang.shp");
    geometry shape <- envelope(plot_shp); 
    
    // Scenarios
    list<string> SCENARIOS <- ["s1", "s2", "s3"];
    map<string, string> SCENARIO_NAMES <- [
	    	"s1"::"Baseline",
	    	"s2"::"Temperature Increase",
	    	"s3"::"AWD Threshold Change"
    ];
    
    // Scenario selection (Just 2 scenes in a simulation)
    string scenario_1 <- "s1";
    string scenario_2 <- "s2";
    
    map<string, map<string, file>> data_files;
    
    string REGIME_CF <- "CF";
    string REGIME_AWD <- "AWD";
    list<string> REGIMES <- [REGIME_CF, REGIME_AWD];
    
    list<string> ORYZA_VARIABLES <- ["water_level", "lai", "soc", "son", "nh3", "n2on", "co2c", "ch4c"];
    map<string, string> COLUMN_MAPPING <- [
        "water_level"::"WL0",
        "lai"::"LAI",
        "soc"::"SOC",
        "son"::"SON",
        "nh3"::"NH3",
        "n2on"::"N2ON",
        "co2c"::"CO2C",
        "ch4c"::"CH4C"
    ];
    
    // Season tracking
    int current_year <- 2015;
    string current_season <- "Winter-Spring 2015-2016";
    int current_season_index <- 1;
    
    // Cast ORYZA output: Multi-scenario data structure: [scenario][regime][variable][rerun_set(season)][doy] -> value
    map<string, map<string, map<string, map<int, map<int, float>>>>> all_data;
    
    // Current simulation data for both scene: [scenario][regime][variable][doy] -> value
    map<string, map<string, map<string, map<int, float>>>> current_data;
    
    // Temperature data (shared between scenarios and regimes): [scenario][rerun_set][doy] -> value
    map<string, map<int, map<int, float>>> temperature_data;
    map<string, map<int, float>> current_temperature_data;
    
    // Current display values: [scenario][regime][variableeter] -> value
    map<string, map<string, map<string, float>>> current_values;
    map<string, float>  current_temperature <- ["s1"::25.0, "s2"::25.0, "s3"::25.0];
    
    // Time management
    list<int> current_doy_steps;
    int current_doy_index <- 0;
    int max_doy_steps;
    int current_doy <- 1;
    
    float max_water_level <- 85.0; // For water level display
    
    // Plot assignments
    map<string, list<int>> regime_plots <- [
        REGIME_CF::[2,4,5],
        REGIME_AWD::[1,3]
    ];
    
    // Season-Year mapping based on rerun set
    map<int, pair<int,string>> rerun_to_season_year;
    
    init {
        create plot from: plot_shp with: [plot_id::int(read("PLOT_ID"))];
        do initialize_data_structures;
        do create_season_year_mapping;
        do build_data_file_mapping;
        do process_selected_scenarios;
	    do set_current_season(1);
        do assign_plot_regimes;
    }

    action initialize_data_structures {
    	list<string> active_scenarios <- [scenario_1, scenario_2];
    	
        loop scenario over: active_scenarios {
        	all_data[scenario] <- [];
        	current_data[scenario] <- [];
        	current_values[scenario] <- [];
        	current_temperature_data[scenario] <- [];
        	
        	loop regime over: REGIMES {
        		all_data[scenario][regime] <- [];
        		current_data[scenario][regime] <- [];
        		current_values[scenario][regime] <- [];
        		
        		loop variable over: ORYZA_VARIABLES {
        			all_data[scenario][regime][variable] <- [];
        			current_data[scenario][regime][variable] <- [];
        			current_values[scenario][regime][variable] <- 0.0;
        			}
        		}
        }
    }
    
    action build_data_file_mapping {
		list<string> active_scenarios <- [scenario_1, scenario_2];
	
    	loop scenario over: active_scenarios {
    		data_files[scenario] <- [];
    		data_files[scenario]["CF"] <- csv_file("../includes/Results/CF_" + scenario + "/cf_res.csv");
    		data_files[scenario]["AWD"] <- csv_file("../includes/Results/AWD_" + scenario + "/awd_res.csv");
    	}
    }
    
	action create_season_year_mapping {
		rerun_to_season_year[1] <- 2015::"Winter-Spring 2015-2016";
		rerun_to_season_year[2] <- 2016::"Summer-Autumn 2016";
		rerun_to_season_year[3] <- 2016::"Winter-Spring 2016-2017";
		rerun_to_season_year[4] <- 2017::"Summer-Autumn 2017";
		rerun_to_season_year[5] <- 2017::"Winter-Spring 2017-2018";
		rerun_to_season_year[6] <- 2018::"Summer-Autumn 2018";
		rerun_to_season_year[7] <- 2018::"Winter-Spring 2018-2019";
		rerun_to_season_year[8] <- 2019::"Summer-Autumn 2019";
		rerun_to_season_year[9] <- 2019::"Winter-Spring 2019-2020";
		rerun_to_season_year[10] <- 2020::"Summer-Autumn 2020";
	}
    
    action process_selected_scenarios {
    	list<string> active_scenarios <- [scenario_1, scenario_2];
    	
    	loop scenario over: active_scenarios {
    		temperature_data[scenario] <- [];
    		loop regime over: REGIMES {
	            if (data_files[scenario] contains_key regime) {
	                do process_all_files(data_files[scenario][regime], scenario, regime);
	            }
	    	}
    	}  
    }
    
    action process_all_files(file regime_file, string scenario, string regime) {
        list<string> headers <- regime_file.attributes;
        matrix<string> data <- matrix(regime_file);
        
        write "Processing " + regime + " file with " + data.rows + " rows";
        
        // Get column indices
        map<string, int> column_indices;
        column_indices["rerun"] <- headers index_of "RERUN_SET";
        column_indices["doy"] <- headers index_of "DOY";
        column_indices["tmax"] <- headers index_of "TMAX";
        column_indices["tmin"] <- headers index_of "TMIN";
        
        // Get indices for all variables
        loop variable over: ORYZA_VARIABLES {
            string column_name <- COLUMN_MAPPING[variable];
            column_indices[variable] <- headers index_of column_name;
        }
        
        // Process each row
        loop i from: 0 to: data.rows - 1 {
            int rerun_set <- int(data[column_indices["rerun"], i]);
            int doy_val <- int(data[column_indices["doy"], i]);
            
            // Store variable values
            loop variable over: ORYZA_VARIABLES {
                float value <- float(data[column_indices[variable], i]);
                do store_value(scenario, regime, variable, rerun_set, doy_val, value);
            }
            
            // Store temperature 
            if (regime = REGIME_CF) {
                float tmax <- float(data[column_indices["tmax"], i]);
                float tmin <- float(data[column_indices["tmin"], i]);
                float avg_temp <- (tmax + tmin) / 2;
                
                if (!(temperature_data[scenario] contains_key rerun_set)) {
                    temperature_data[scenario][rerun_set] <- [];
                }
                temperature_data[scenario][rerun_set][doy_val] <- avg_temp;
            }
        }      
        write "Completed processing " + regime + " file";
    }
    
    action store_value(string scenario, string regime, string variable, int rerun_set, int doy, float value) {
        if (!(all_data[scenario][regime][variable] contains_key rerun_set)) {
            all_data[scenario][regime][variable][rerun_set] <- [];
        }
        all_data[scenario][regime][variable][rerun_set][doy] <- value;
    }
    
    action set_current_season(int season_index) {
        current_season_index <- season_index;
        
        if (rerun_to_season_year contains_key season_index) {
            pair<int,string> season_year <- rerun_to_season_year[season_index];
            current_year <- season_year.key;
            current_season <- season_year.value;
            
            list<string> active_scenarios <- [scenario_1, scenario_2];
            
            // Load data for current season
            loop scenario over: active_scenarios {
	            loop regime over: REGIMES {
	                loop variable over: ORYZA_VARIABLES {
	                    if (all_data[scenario][regime][variable] contains_key season_index) {
	                        current_data[scenario][regime][variable] <- all_data[scenario][regime][variable][season_index];
	                    } else {
	                        current_data[regime][variable] <- [];
	                    }
	                }
	            } 
	            
	            if (temperature_data[scenario] contains_key season_index) {
	            	current_temperature_data[scenario] <- temperature_data[scenario][season_index];
	            } else {
	            	current_temperature_data[scenario] <- [];
	            }         	
            }

            // Get DOY steps 
            current_doy_steps <- current_data[scenario_1][REGIME_CF]["water_level"].keys;
            current_doy_steps <- current_doy_steps sort_by each;
            max_doy_steps <- length(current_doy_steps);
            current_doy_index <- 0;
        }
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
    
    reflex update_simulation when: current_doy_index < max_doy_steps {
        current_doy <- current_doy_steps[current_doy_index];
        
        list<string> active_scenarios <- [scenario_1, scenario_2];
        
        // Update all current values
        loop scenario over: active_scenarios {
        	loop regime over: REGIMES {
	            loop variable over: ORYZA_VARIABLES {
	                if (current_data[scenario][regime][variable] contains_key current_doy) {
	                    current_values[scenario][regime][variable] <- current_data[scenario][regime][variable][current_doy];
	                }
	            }
	        }
	        
	        if (current_temperature_data[scenario] contains_key current_doy) {
	        	current_temperature[scenario] <- current_temperature_data[scenario][current_doy];
	        }
        }
        
        // Update plots
        ask plot {
            if (regime != "None") {
                water_level_s1 <- min([max([current_values[scenario_1][regime]["water_level"], 0.0]), max_water_level]);
                water_level_s2 <- min([max([current_values[scenario_2][regime]["water_level"], 0.0]), max_water_level]);
            }
        }
        
        current_doy_index <- current_doy_index + 1;
    }
    
    reflex next_season when: current_doy_index >= max_doy_steps {
        int next_season <- current_season_index + 1;
        if (next_season <= 10) {
            do set_current_season(next_season);
        } else {
            write "Simulation completed all seasons 2015-2020";
            do pause;
        }
    }
    
    // Get current value for a regime and variable
    float get_current_value(string scenario, string regime, string variable) {
        if (current_values contains_key scenario and 
            current_values[scenario] contains_key regime and
            current_values[scenario][regime] contains_key variable) {
            return current_values[scenario][regime][variable];
        }
        return 0.0;
    }
    
    // Navigation actions
    action go_to_season(int season_index) {
        if (season_index >= 1 and season_index <= 10) {
            do set_current_season(season_index);
        }
    }
    
    action go_to_previous_season {
        if (current_season_index > 1) {
            do set_current_season(current_season_index - 1);
        }
    }
    
    action go_to_next_season {
        if (current_season_index < 10) {
            do set_current_season(current_season_index + 1);
        }
    }
    
    action change_scenarios(string new_scenario_1, string new_scenario_2) {
    	if (new_scenario_1 != scenario_1 or new_scenario_2 != scenario_2) {
    		scenario_1 <- new_scenario_1;
    		scenario_2 <- new_scenario_2;
    		//write "Switching to compare: " + SCENARIO_NAMES[scenario_1] + " vs " + SCENARIO_NAMES[scenario_2];
    	    do initialize_data_structures;
    	    do build_data_file_mapping;
    	    do process_selected_scenarios;
    	    do set_current_season(current_season_index);
    	    
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
    	
    	string scenario_1_name <- SCENARIO_NAMES[scenario_1];
    	
    	draw string(scenario_1_name + ": " + water_level_s1 with_precision 1 + "mm")
    		color: #white size: 10 at: {location.x, location.y - 8};
    }
    
    aspect scenario_2 {
    	rgb plot_color <- calculate_water_color_s2();
    	draw shape color: plot_color border: #black width: 2;
    	draw string(regime);
    	
    	string scenario_2_name <- SCENARIO_NAMES[scenario_2];
    	
    	draw string(scenario_2_name + ": " + water_level_s2 with_precision 1 + "mm")
    		color: #white size: 10 at: {location.x, location.y -8};
    }
    
    aspect default {
        rgb plot_color <- calculate_combined_water_color();
        draw shape color: plot_color border: #black width: 2;
        draw string(plot_id) color: #white size: 11 at: location;
        
        string scenario_1_name <- SCENARIO_NAMES[scenario_1];
        string scenario_2_name <- SCENARIO_NAMES[scenario_2];
        
        draw string(scenario_1_name + ": " + water_level_s1 with_precision 1 + "mm")
            color: #white size: 10 at: {location.x, location.y - 8};
        draw string(scenario_2_name + ": " + water_level_s2 with_precision 1 + "mm")
            color: #yellow size: 10 at: {location.x, location.y - 16};
    }
    
    rgb calculate_combined_water_color {
        float avg_water_level <- (water_level_s1 + water_level_s2) / 2.0;
        if (avg_water_level <= 0.0) {
            return rgb(139, 119, 101);
        } else {
            float water_ratio <- avg_water_level / max_water_level;
            int blue_intensity <- int(255 - (water_ratio * 205));
            blue_intensity <- max([50, min([255, blue_intensity])]);
            int green_component <- int(blue_intensity * 0.3);
            return rgb(0, green_component, blue_intensity);
        }
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
    float minimum_cycle_duration <- 0.01#s;
    parameter "Scenario 1" var: scenario_1 category: "Scenario Selection" among: SCENARIOS;
    parameter "Scenario 2" var: scenario_2 category: "Scenario Selection" among: SCENARIOS;
    
    output synchronized: false {
        layout vertical([
        	horizontal([0::5000, 1::5000])::5000,
        	horizontal([2::5000, 3::5000])::5000
        ])
        
        editors: false toolbars: false;
        
        display map_s1 type: 2d {
            species plot aspect: scenario_1;
        }
        
        display map_s2 type: 2d {
        	species plot aspect: scenario_2;
        }
        
        display "Water Level/Temperature Comparison" type: 2d {
            chart "" type: series background: #white 
                y_label: "Water level (mm)" y2_label: "Temperature (°C)" {
                
                // Scenario 1 
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "water_level") 
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "water_level") 
                    color: #red marker: false style: line;
                
                // Scenario 2 
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "water_level") 
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "water_level") 
                    color: #darkred marker: false style: line;
                
                // Temperature
                data (SCENARIO_NAMES[scenario_1] + " Temp") 
                    value: current_temperature[scenario_1] 
                    use_second_y_axis: true color: #chartreuse marker: false style: step;
                data (SCENARIO_NAMES[scenario_2] + " Temp") 
                    value: current_temperature[scenario_2] 
                    use_second_y_axis: true color: #orange marker: false style: step;
            }
        }
        
        display "LAI Comparison" type: 2d {
            chart "Leaf Area Index Comparison" type: series background: #white {
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "lai") 
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "lai") 
                    color: #red marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "lai") 
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "lai") 
                    color: #darkred marker: false style: line;
            }
        }
    }
}

experiment emission type: gui {
    float minimum_cycle_duration <- 0.1#s;
    parameter "Scenario 1" var: scenario_1 category: "Scenario Selection" among: SCENARIOS;
    parameter "Scenario 2" var: scenario_2 category: "Scenario Selection" among: SCENARIOS;

    output synchronized: false {
        layout vertical([
            horizontal([0::5000, 1::5000])::5000,
            horizontal([2::5000, 3::5000])::5000
        ])
        editors: false toolbars: false;

        display "N2O Comparison" type: 2d {
            chart "Nitrous Oxide Comparison" type: series background: #white
            y_label: "N2O Level (per ha)" {
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "n2on")
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "n2on")
                    color: #red marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "n2on")
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "n2on")
                    color: #darkred marker: false style: line;
            }
        }

        display "SOC Comparison" type: 2d {
            chart "Soil Organic Carbon Comparison" type: series background: #white
            y_label: "SOC Level (per ha)" {
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "soc")
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "soc")
                    color: #red marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "soc")
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "soc")
                    color: #darkred marker: false style: line;
            }
        }

        display "CO2 Comparison" type: 2d {
            chart "CO2 Comparison" type: series background: #white
            y_label: "CO2 (per ha)" {
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "co2c")
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "co2c")
                    color: #red marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "co2c")
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "co2c")
                    color: #darkred marker: false style: line;
            }
        }

        display "CH4 Comparison" type: 2d {
            chart "CH4 Comparison" type: series background: #white
            y_label: "CH4 (per ha)" {
                data (SCENARIO_NAMES[scenario_1] + " CF") 
                    value: get_current_value(scenario_1, REGIME_CF, "ch4c")
                    color: #blue marker: false style: line;
                data (SCENARIO_NAMES[scenario_1] + " AWD") 
                    value: get_current_value(scenario_1, REGIME_AWD, "ch4c")
                    color: #red marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " CF") 
                    value: get_current_value(scenario_2, REGIME_CF, "ch4c")
                    color: #darkblue marker: false style: line;
                data (SCENARIO_NAMES[scenario_2] + " AWD") 
                    value: get_current_value(scenario_2, REGIME_AWD, "ch4c")
                    color: #darkred marker: false style: line;
            }
        }
    }
}