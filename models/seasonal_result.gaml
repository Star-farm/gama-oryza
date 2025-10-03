/**
* Name: seasonalresult
* Based on the internal empty template. 
* Author: pc
* Tags: 
*/

model seasonal_result

global {
    matrix cf_s1;
    matrix cf_s2;
    matrix cf_s3;
    matrix awd_s1;
    matrix awd_s2;
    matrix awd_s3;
    
    int WRR14 <- 1;
    int RAINCUM <- 3;
    int IRCUM <- 4;
    int SOC <- 5;
    int SON <- 6;
    int S_CH4C <- 7;
    
    list<string> season_labels <- ["W-S 15-16","S-A 16","W-S 16-17","S-A 17","W-S 17-18","S-A 18","W-S 18-19","S-A 19","W-S 19-20","S-A 20"];
    
    init {
        do load_data;
    }
    
    action load_data {
        cf_s1 <- csv_file("../includes/Results/CF_s1/cf_op.csv");
        cf_s2 <- csv_file("../includes/Results/CF_s2/cf_op.csv");
        cf_s3 <- csv_file("../includes/Results/CF_s3/cf_op.csv");
        awd_s1 <- csv_file("../includes/Results/AWD_s1/awd_op.csv");
        awd_s2 <- csv_file("../includes/Results/AWD_s2/awd_op.csv");
        awd_s3 <- csv_file("../includes/Results/AWD_s3/awd_op.csv");
    }
    
    list<float> get_column_values(matrix data, int col_index) {
    		list<float> values <- [];
	    	loop i from: 0 to: data.rows - 1 {
	    		values <- values + float(data[col_index, i]);
	    	}
	    	
	    	return values;
    }
}

experiment "Yield" type: gui {
    output {
        //layout horizontal([1::1, 1::1, 1::1]);
        
        display "Yield Distribution - Scenario 1" type: 2d{
            chart "Yield (kg/ha) - Scenario 1" type: histogram background: #white x_serie_labels: season_labels series_label_position: none{
                data "CF Treatment" value: get_column_values(cf_s1, WRR14)
                    color: #blue;
                data "AWD Treatment" value: get_column_values(awd_s1, WRR14) 
                    color: #red;
            }
        }
        
        display "Yield Distribution - Scenario 2" type: 2d{
            chart "Yield (kg/ha) - Scenario 2" type: histogram background: #white x_serie_labels: season_labels series_label_position: none{
                data "CF Treatment" value: get_column_values(cf_s2, WRR14) 
                    color: #blue;
                data "AWD Treatment" value: get_column_values(awd_s2, WRR14)
                    color: #red;
            }
        }
        
        display "Yield Distribution - Scenario 3" type: 2d{
            chart "Yield (kg/ha) - Scenario 3" type: histogram background: #white x_serie_labels: season_labels series_label_position: none{
                data "CF Treatment" value: get_column_values(cf_s3, WRR14) 
                    color: #blue;
                data "AWD Treatment" value: get_column_values(awd_s3, WRR14) 
                    color: #red;
            }
        }
    }
}

experiment "Irrigation" type: gui {
    output {
        display "Water Use Comparison - All Scenarios" type: 2d {
            chart "Water Use (mm) - All Scenarios" type: series background: #white x_serie_labels: season_labels {
                data "CF Scenario 1" value: get_column_values(cf_s1, IRCUM) color: #blue;
                data "AWD Scenario 1" value: get_column_values(awd_s1, IRCUM) color: #red;
                data "CF Scenario 2" value: get_column_values(cf_s2, IRCUM) color: #darkblue;
                data "AWD Scenario 2" value: get_column_values(awd_s2, IRCUM) color: #darkred;
                //data "CF Scenario 3" value: get_column_values(cf_s3, IRCUM) color: #dodgerblue;
                data "AWD Scenario 3" value: get_column_values(awd_s3, IRCUM) color: #coral;
            }
        }
    }
}

experiment "Methane" type: gui {
    output {
        display "CH4 Emissions Comparison - All Scenarios" type: 2d{
            chart "CH4 Emissions (kg/ha) - All Scenarios" type: series background: #white x_serie_labels: season_labels{
                data "CF Scenario 1" value: get_column_values(cf_s1, S_CH4C) color: #blue;
                data "AWD Scenario 1" value: get_column_values(awd_s1, S_CH4C) color: #red;
                data "CF Scenario 2" value: get_column_values(cf_s2, S_CH4C) color: #darkblue;
                data "AWD Scenario 2" value: get_column_values(awd_s2, S_CH4C) color: #darkred;
                //data "CF Scenario 3" value: get_column_values(cf_s3, S_CH4C) color: #dodgerblue;
                data "AWD Scenario 3" value: get_column_values(awd_s3, S_CH4C) color: #coral;
            }
        }
    }
}

