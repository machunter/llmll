use hangman_complete::*;
use std::io::{self, Write};

fn main() {
    println!("Welcome to LLMLL Hangman!\n");
    
    // Initialize game with a secret word
    let word = LlmllVal::from("llmll".to_string());
    let input = LlmllVal::Adt("StartGame".to_string(), vec![word]);
    
    // Pass empty string as initial dummy state for game_step StartGame
    let init_result = game_step(LlmllVal::from("".to_string()), input);
    
    // game_step returns a Pair(state, command)
    let mut current_state = first(init_result.clone());
    let cmd = second(init_result.clone());
    
    println!("{}", cmd.into_string());
    
    loop {
        print!("Enter a letter guess: ");
        io::stdout().flush().unwrap();
        
        let mut guess = String::new();
        io::stdin().read_line(&mut guess).unwrap();
        let guess = guess.trim().to_string();
        
        if guess.is_empty() {
             continue;
        }
        
        let letter = guess.chars().next().unwrap().to_string();
        
        // Next input is Guess
        let input = LlmllVal::Adt("Guess".to_string(), vec![LlmllVal::from(letter)]);
        let step_result = game_step(current_state.clone(), input);
        
        current_state = first(step_result.clone());
        let cmd = second(step_result.clone());
        
        println!("\n{}\n", cmd.into_string());
        
        let status = game_status(current_state.clone());
        if status.as_str() == "won" {
            println!("Congratulations! You won!");
            println!("The word was: {}", state_word(current_state.clone()).as_str());
            break;
        } else if status.as_str() == "lost" {
            println!("Game Over! You lost!");
            println!("The word was: {}", state_word(current_state.clone()).as_str());
            break;
        }
    }
}
