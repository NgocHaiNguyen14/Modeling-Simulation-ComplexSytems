/**
* Name: FluVirusVariants
* Description: Model of flu virus spread with family structures, vaccination, and variants
*/

model FluVirusVariants

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
    int nb_families <- 4000;
    float base_infection_probability <- 0.33;
    int isolation_duration <- 12;
    float test_percentage <- 0.01;
    
    // Vaccination parameters
    float vaccination_rate <- 0.0005; // 0.05% per day
    float base_vaccine_protection <- 3.0;
    
    // Variant parameters
    float mutation_probability <- 0.001; // 0.1% chance
    map<string, float> variant_infection_rates <- ["original"::base_infection_probability];
    string current_vaccine_target <- "original";
    list<string> existing_variants <- ["original"];
    int variant_counter <- 0;
    
    // Time settings
    float step <- 1 #hour;
    int start_work <- 8;
    int end_work <- 17;
    bool is_working_hour <- false update: current_date.hour >= start_work and current_date.hour < end_work;
    
    // Statistics
    int total_vaccinated -> {length(person where each.is_vaccinated)};
    float vaccination_percentage -> {(total_vaccinated / length(person)) * 100};
    map<string, int> variant_cases -> {get_variant_cases()};
    
    // Helper action for variant cases
    map<string, int> get_variant_cases {
        map<string, int> cases;
        loop variant over: existing_variants {
            cases[variant] <- person count (each.current_variant = variant and each.is_infected);
        }
        return cases;
    }
    
    // Action for creating new variants
    action generate_new_variant (string parent_variant) type: string {
        variant_counter <- variant_counter + 1;
        string new_variant <- "variant_" + variant_counter;
        float parent_rate <- variant_infection_rates[parent_variant];
        float mutation_factor <- 0.5 + rnd(1.0); // Random between 0.5 and 1.5
        variant_infection_rates[new_variant] <- parent_rate * mutation_factor;
        existing_variants <+ new_variant;
        write "New variant emerged: " + new_variant + " with infection rate: " + (variant_infection_rates[new_variant]);
        return new_variant;
    }
    
    init {
        // Create buildings
        create building from: shapefile_buildings;
        school <- building with_max_of(each.shape.area);
        school.is_school <- true;
        residential_buildings <- building where (!each.is_school);
        work_buildings <- residential_buildings;
        
        // Create roads
        create road from: shapefile_roads;
        road_network <- as_edge_graph(road);
        
        // Create families
        create family number: nb_families {
            home_building <- one_of(residential_buildings);
            location <- any_location_in(home_building);
            
            nb_members <- rnd(3,6);
            nb_children <- rnd(0, min(2, nb_members - 2));
            nb_adults <- nb_members - nb_children;
            
            // Create adults
            create person number: nb_adults {
                my_family <- myself;
                home <- myself.location;
                age_category <- "adult";
                workplace <- any_location_in(one_of(myself.home_building));
                location <- home;
                size <- 3.0;
            }
            
            // Create children
            create person number: nb_children {
                my_family <- myself;
                home <- myself.location;
                age_category <- "child";
                workplace <- any_location_in(school);
                location <- home;
                size <- 3.0;
            }
        }
        
        // Initialize with some infected people
        ask (length(person) * 0.005) among person {
            is_infected <- true;
            infection_time <- current_date;
            current_variant <- "original";
            infection_history <+ "original";
        }
    }
    
    reflex virus_mutation when: every(24 #hour) {
        ask person where (each.is_infected) {
            if flip(mutation_probability) {
                string new_variant <- myself.generate_new_variant(self.current_variant);
                self.current_variant <- new_variant;
            }
        }
    }
    
    reflex update_vaccine_target when: every(24 #hour) {
        string most_prevalent_variant <- existing_variants with_max_of(variant_cases[each]);
        if (most_prevalent_variant != current_vaccine_target) {
            write "Vaccine target updated to: " + most_prevalent_variant;
            current_vaccine_target <- most_prevalent_variant;
        }
    }
    
    reflex daily_testing when: every(24 #hour) {
        list<person> untested_people <- person where (!each.is_isolated);
        int num_to_test <- max(1, int(length(untested_people) * test_percentage));
        ask num_to_test among untested_people {
            if (is_infected) {
                is_isolated <- true;
                isolation_start <- current_date;
                ask my_family.members {
                    is_isolated <- true;
                    isolation_start <- current_date;
                }
            }
        }
    }
    
    reflex daily_vaccination when: every(24 #hour) {
        list<person> unvaccinated_people <- person where (!each.is_vaccinated and !each.is_infected and !each.is_isolated);
        int num_to_vaccinate <- max(1, int(length(unvaccinated_people) * vaccination_rate));
        ask num_to_vaccinate among unvaccinated_people {
            is_vaccinated <- true;
            vaccination_time <- current_date;
            vaccine_variant <- current_vaccine_target;
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
    bool is_vaccinated <- false;
    string current_variant <- nil;
    string vaccine_variant <- nil;
    list<string> infection_history <- [];
    date infection_time;
    date isolation_start;
    date vaccination_time;
    int infection_duration <- rnd(2,8);
    
    // Movement
    float speed <- 30 #km/#h;
    
    float get_infection_probability(person infected_person) {
        float base_prob <- variant_infection_rates[infected_person.current_variant];
        if (is_vaccinated) {
            float vaccine_effectiveness <- (vaccine_variant = infected_person.current_variant) ? base_vaccine_protection : base_vaccine_protection / 2;
            base_prob <- base_prob / vaccine_effectiveness;
        }
        if (infection_history contains infected_person.current_variant) {
            return 0.0;
        }
        return base_prob;
    }
    
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
    
    reflex infect when: is_infected and !is_isolated {
        // Family infections
        ask my_family.members where (!each.is_infected and !each.is_isolated) {
            float effective_probability <- myself.get_infection_probability(myself) * 1.5;
            if flip(effective_probability) {
                is_infected <- true;
                infection_time <- current_date;
                current_variant <- myself.current_variant;
                infection_history <+ current_variant;
            }
        }
        
        // Other infections
        ask (person at_distance 2#m) where (!each.is_infected and !each.is_isolated and !(my_family.members contains each)) {
            float effective_probability <- myself.get_infection_probability(myself);
            if flip(effective_probability) {
                is_infected <- true;
                infection_time <- current_date;
                current_variant <- myself.current_variant;
                infection_history <+ current_variant;
            }
        }
    }
    
    reflex recover when: is_infected {
        if (current_date - infection_time > infection_duration #day) {
            is_infected <- false;
            current_variant <- nil;
        }
    }
    
    reflex end_isolation when: is_isolated {
        if (current_date - isolation_start > isolation_duration #day) {
            is_isolated <- false;
        }
    }
    
    aspect default {
        rgb agent_color <- #green;
        if (is_isolated) { agent_color <- #gray; }
        else if (is_infected) { 
            // Different colors for different variants
            agent_color <- rgb(255 * (variant_infection_rates[current_variant] / base_infection_probability), 0, 0);
        }
        else if (is_vaccinated) { agent_color <- #blue; }
        draw circle(size) color: agent_color;
    }
}

experiment flu_simulation type: gui {
    parameter "Number of families" var: nb_families min: 100 max: 10000 category: "Population";
    parameter "Base infection probability" var: base_infection_probability min: 0.0 max: 1.0 category: "Disease";
    parameter "Mutation probability" var: mutation_probability min: 0.0 max: 0.01 category: "Disease";
    parameter "Test percentage" var: test_percentage min: 0.0 max: 0.1 category: "Control";
    parameter "Vaccination rate" var: vaccination_rate min: 0.0 max: 0.01 category: "Vaccination";
    
    output {
        layout #split;
        
        display city_display type: opengl {
            species building aspect: default;
            species road aspect: default;
            species person aspect: default;
        }
        
        display charts refresh: every(10 #cycles) {
            chart "Variant Cases" type: series position: {0, 0} size: {1.0, 0.5} {
                loop variant over: existing_variants {
                    data variant value: variant_cases[variant] color: rgb(rnd(255), rnd(255), rnd(255));
                }
            }
            
            chart "Population Status" type: series position: {0, 0.5} size: {1.0, 0.5} {
                data "Total Infected" value: person count (each.is_infected) color: #red;
                data "Vaccinated" value: total_vaccinated color: #blue;
                data "Isolated" value: person count (each.is_isolated) color: #gray;
            }
        }
        
        monitor "Total Population" value: length(person);
        monitor "Active Variants" value: length(existing_variants);
        monitor "Current Vaccine Target" value: current_vaccine_target;
        monitor "Vaccination Coverage (%)" value: round(vaccination_percentage * 100) / 100;
    }
}
