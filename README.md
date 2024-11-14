## NOTE

- assumed rewards are in contract

- send data cross-chain when someone:
  - deposits
  - withdraws

calcAccumulatedInterestSinceLastUpdate

```
block number: 1
  calcAccumulatedInterestSinceLastUpdate: 1000000000000000000000000000

  block number: 101
  calcAccumulatedInterestSinceLastUpdate: 1000000000000000000050000000

  block number: 201
  calcAccumulatedInterestSinceLastUpdate: 1000000000000000000100000000
```

super.balanceOf

```block number: 1
  super.balanceOf: 100000

  block number: 101
  super.balanceOf: 100000

  block number: 201
 super.balanceOf: 100000
```

userAccumulatedRate

```
block number: 1
  user accumulated interest: 1000000000000000000000000000
block 101
  user accumulated interest: 1000000000000000000000000000
block 201
  user accumulated interest: 1000000000000000000000000000
```

calculation

```
function getAccumulatedInterestSinceLastUpdate(address _user) external view returns (uint256) {
        return super.balanceOf(_user) * _calculateAccumulatedInterestSinceLastUpdate() / s_userAccumulatedRates[_user];
    }
```
