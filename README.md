## NOTE

- send data cross-chain when someone:
  - deposits
  - withdraws

calcAccumulatedInterestSinceLastUpdate

```
block number: 1
  block timestamp: 1
  User start balance: 100000
  accumulated interest: 1000000000000000000000000000
  block number: 101
  block timestamp: 101
  User middle balance: 100000
  accumulated interest: 1000000000000000000050000000
  block number: 201
  block timestamp: 201
  User end balance: 100000
  accumulated interest: 1000000000000000000100000000
```

super.balanceOf

```block number: 1
  accumulated interest: 100000

  block number: 101
  accumulated interest: 100000

  block number: 201
  accumulated interest: 100000
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
