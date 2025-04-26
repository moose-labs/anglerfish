# Anglerfish: Gamified DeFi on Sui

**Anglerfish** is a decentralized finance (DeFi) project built on the Sui blockchain, designed to make yield generation and lottery participation engaging and rewarding through gamification. It combines robust yield strategies with the thrill of a lottery mechanism, all within a transparent and secure on-chain environment.

## Project Structure

The repository is organized into the following key directories:

- **`contracts/core/`**: This directory houses the core business logic of the Anglerfish protocol. It contains the smart contracts and modules responsible for:
  - **Pools**: Management of yield-generating pools, including deposit and withdrawal functionalities, and integration with underlying yield sources.
  - **PrizePool**: Implementation of the lottery mechanism, including ticket purchasing, random number generation (utilizing Sui's capabilities), and prize distribution.
- **`contracts/libs/math/`**: This directory contains reusable mathematical libraries and utility functions used throughout the project, ensuring precision and efficiency in calculations.

## Key Features

- **Gamified Yield Generation:** Earn yield on your deposited assets while participating in a lottery system, adding an element of excitement to traditional DeFi earning.
- **Transparent Lottery Mechanism:** Leveraging the security and transparency of the Sui blockchain, the lottery draws are verifiable and fair.
- **Modular Design:** The separation of core logic into `core` and reusable utilities in `libs/math` promotes maintainability and scalability.
- **Built on Sui:** Utilizing the unique features of the Sui blockchain, such as its object-centric model and high transaction throughput, to deliver a seamless user experience.

## Getting Started (Development)

This section outlines the steps for developers looking to set up and work on the Anglerfish project.

### Prerequisites

- **Sui Toolchain:** Ensure you have the Sui development environment installed and configured. Refer to the official Sui documentation for installation instructions.
- **Move Language:** Familiarity with the Move programming language is essential for understanding and contributing to the smart contracts.

### Setting Up the Project

1.  **Clone the Repository:**

    ```bash
    git clone https://github.com/moose-labs/anglerfish.git
    cd contracts/core
    ```

2.  **Navigate to the Core Directory:**

    ```bash
    cd core
    ```

3.  **Build the Smart Contracts:**

    ```bash
    sui move build
    ```

    This command compiles the Move smart contracts located within the `core` directory.

4.  **Explore the Code:**
    - Examine the modules within the `core/pool` directory to understand the yield pool logic.
    - Review the modules within the `core/prizepool` directory to understand the lottery mechanism.
    - Inspect the mathematical utilities in the `libs/math` directory.

### Testing

Comprehensive testing is crucial for the security and reliability of DeFi protocols. Refer to the testing setup and instructions within the respective directories (`core` and potentially a dedicated `tests` directory if one exists). You will likely use the Sui CLI for running unit and integration tests.

## Contributing

We welcome contributions to the Anglerfish project! If you're interested in contributing, please follow these guidelines:

1.  **Fork the Repository:** Create your own fork of the Anglerfish repository.
2.  **Create a Branch:** Make your changes in a dedicated branch.
3.  **Code Style:** Adhere to the coding conventions used throughout the project.
4.  **Testing:** Ensure your changes are thoroughly tested.
5.  **Pull Request:** Submit a pull request with a clear description of your changes.

## License

[Specify the project's license here, e.g., Apache 2.0]

## Disclaimer

Anglerfish is under active development and is provided "as is" without any warranties. Use it at your own risk. Engaging with DeFi protocols involves inherent risks, including but not limited to smart contract risks, market volatility, and potential loss of funds.

## Contact

[Provide contact information or links to community channels, e.g., Discord, Telegram]
