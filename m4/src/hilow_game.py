"""Play a higher/lower guessing game with user-defined bounds.

Inputs:
- lower_bound (int) from user input
- upper_bound (int) from user input
- user_guess (int) from user input

Processing:
- Validate bounds so lower < upper
- Generate a random number in the range
- Compare guesses until the random number is guessed

Outputs:
- Prompts, hints (too low/high), and success message printed to the console.

Typical usage example:
    Enter the lower bound: 1
    Enter the upper bound: 10
    Great, now guess a number between 1 and 10: 5
    Nope, too low.
    Guess another number: 7
    You got it!
"""

# === Imports ===
from random import randint


# === Main Function ===
def main() -> None:
    """Run the higher/lower guessing game."""

    # Display welcome message to Bella.
    print("Welcome to the higher/lower game, Bella!")

    # Get and validate lower and upper bounds of the guessing range.
    while True:
        lower_bound = int(input("Enter the lower bound: "))
        upper_bound = int(input("Enter the upper bound: "))

        if lower_bound >= upper_bound:
            print("The lower bound must be less than the upper bound.")

        print()  # blank line per sample output

        if lower_bound < upper_bound:  # sentinel condition for loop
            break

    # Generate a random number between lower and upper bounds, inclusive.
    secret_number = randint(lower_bound, upper_bound)

    # Prompt player for first guess.
    user_guess = int(
        input(
            f"Great, now guess a number between {lower_bound} and "
            f"{upper_bound}: "
        )
    )

    # Repeat guessing until the user guesses correctly.
    while user_guess != secret_number:
        if user_guess < lower_bound or user_guess > upper_bound:
            print(
                f"Your guess must be between {lower_bound} "
                f"and {upper_bound}."
            )
        elif user_guess < secret_number:
            print("Nope, too low.")
        else:
            print("Nope, too high.")

        user_guess = int(input("\nGuess another number: "))

    # Display correct guess message.
    print("You got it!\n")


# === Main Guard ===
if __name__ == "__main__":
    main()


# === References ===
# TODO: Add references to any resources used to complete this assignment.
