/**
* Name: FluVirusFamily
* Description: Model of flu virus spread with family structures
*/

model FluVirusFamily

global {
    // GIS data
    shape_file shapefile_buildings <- shape_file("../includes/buildings.shp");
    shape_file shapefile_roads <- shape_file("../includes/clean_roads.shp");
    
    // Environment
    geometry shape <- envelope(shapefile_roads);
    graph road_network;
    
    // Building categorization
    building school <- nil;
    list<building> residential_buildings;
    list<building> work_buildings;
    
    // Population parameters
    int nb_families <- 4000; // Adjusted for larger population
    float infection_probability <- 0.33;
    int isolation_duration <- 12;
    float test_percentage <- 0.01;
    
    // Time settings
    float step <- 1 #hour;
    int start_work <- 8;
    int end_work <- 17;
    bool is_working_hour <- false update: current_date.hour >= start_work and current_date.hour < end_work;
    
    init {
        // Create buildings
        create building from: shapefile_buildings;
        
        // Set up school (largest building)
        school <- building with_max_of(each.shape.area);
        school.is_school <- true;
        
        // Categorize other buildings
        residential_buildings <- building where (!each.is_school);
        work_buildings <- residential_buildings;
        
        // Create roads
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        // Create families and populate them
        create family number: nb_families {
            // Assign home
            home_building <- one_of(residential_buildings);
            location <- any_location_in(home_building);
            
            // Create family members (3-6 people per family)
            nb_members <- rnd(3,6);
            nb_children <- rnd(0, min(2, nb_members - 2)); // 0-2 children, ensuring at least 2 adults
            nb_adults <- nb_members - nb_children;
            
            // Create adults
            create person number: nb_adults {
                my_family <- myself;
                home <- myself.location;
                age_category <- "adult";
                workplace <- any_location_in(one_of(myself.home_building));
                location <- home;
                size <- 3.0; // Smaller size for visualization
            }
            
            // Create children
            create person number: nb_children {
                my_family <- myself;
                home <- myself.location;
                age_category <- "child";
                workplace <- any_location_in(school); // Children go to school
                location <- home;
                size <- 3.0; // Smaller size for visualization
            }
        }
        
        // Initialize with some infected people (0.5% of population)
        ask (length(person) * 0.005) among person {
            is_infected <- true;
            infection_time <- current_date;
        }
    }
    
    // Daily testing reflex
    reflex daily_testing when: every(24 #hour) {
        list<person> untested_people <- person where (!each.is_isolated);
        int num_to_test <- max(1, int(length(untested_people) * test_percentage));
        ask num_to_test among untested_people {
            if (is_infected) {
                is_isolated <- true;
                isolation_start <- current_date;
                
                // Isolate whole family
                ask my_family.members {
                    is_isolated <- true;
                    isolation_start <- current_date;
                }
            }
        }
    }
}

species building {
    bool is_school <- false;
    
    aspect default {
        draw shape color: is_school ? #blue : #gray;
    }
}

species road {
    aspect default {
        draw shape color: #black width: 2;
    }
}

species family {
    building home_building;
    point location;
    int nb_members;
    int nb_adults;
    int nb_children;
    list<person> members <- [] update: person where (each.my_family = self);
}

species person skills: [moving] {
    // Family info
    family my_family;
    string age_category;
    float size;
    
    // Locations
    point home;
    point workplace;
    point target;
    
    // Disease status
    bool is_infected <- false;
    bool is_isolated <- false;
    date infection_time;
    date isolation_start;
    int infection_duration <- rnd(2,8);
    
    // Movement
    float speed <- 30 #km/#h;
    
    reflex go_to_work when: !is_isolated and is_working_hour and location = home {
        target <- workplace;
    }
    
    reflex return_home when: !is_isolated and !is_working_hour and location = workplace {
        target <- home;
    }
    
    reflex move when: target != nil {
        do goto target: target on: road_network;
        if (location distance_to target < 2#m) {
            location <- target;
            target <- nil;
        }
    }
    
    // Disease dynamics
    reflex infect when: is_infected and !is_isolated {
        // Higher infection probability within family
        ask my_family.members where (!each.is_infected and !each.is_isolated) {
            if flip(infection_probability * 1.5) { // 50% higher chance within family
                is_infected <- true;
                infection_time <- current_date;
            }
        }
        
        // Normal infection probability for others in proximity
        ask (person at_distance 2#m) where (!each.is_infected and !each.is_isolated and !(my_family.members contains each)) {
            if flip(infection_probability) {
                is_infected <- true;
                infection_time <- current_date;
            }
        }
    }
    
    reflex recover when: is_infected {
        if (current_date - infection_time > infection_duration #day) {
            is_infected <- false;
        }
    }
    
    reflex end_isolation when: is_isolated {
        if (current_date - isolation_start > isolation_duration #day) {
            is_isolated <- false;
        }
    }
    
    aspect default {
        draw circle(size) color: is_isolated ? #gray : (is_infected ? #red : #green);
    }
}

experiment flu_simulation type: gui {
    parameter "Number of families" var: nb_families min: 100 max: 10000 category: "Population";
    parameter "Infection probability" var: infection_probability min: 0.0 max: 1.0 category: "Disease";
    parameter "Test percentage" var: test_percentage min: 0.0 max: 0.1 category: "Control";
    
    output {
        layout #split;  // This ensures a split layout
        
        display city_display type: opengl {  // Using opengl for better performance with large populations
            species building aspect: default;
            species road aspect: default;
            species person aspect: default;
        }
        
        display disease_charts refresh: every(10 #cycles) {  // Separate display for disease charts
            chart "Disease Status" type: series position: {0, 0} size: {1.0, 0.5} {
                data "Infected" value: person count (each.is_infected) color: #red;
                data "Susceptible" value: person count (!each.is_infected) color: #green;
                data "Isolated" value: person count (each.is_isolated) color: #gray;
            }
            
            chart "Population Categories" type: pie position: {0, 0.5} size: {1.0, 0.5} {
                data "Adults" value: person count (each.age_category = "adult") color: #orange;
                data "Children" value: person count (each.age_category = "child") color: #blue;
            }
        }
        
        // Monitors will appear in the parameters section
        monitor "Total Population" value: length(person);
        monitor "Number of Families" value: length(family);
        monitor "Average Family Size" value: round(length(person) / length(family) * 100) / 100;
    }
}