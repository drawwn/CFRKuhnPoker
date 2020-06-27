//
//  CFRKuhn.swift
//  Holdem
//
//  Created by Daniel McLean on 6/21/20.
//  Copyright © 2020 Daniel McLean. All rights reserved.
//
// Based on this post by Thomas Trenner
// https://medium.com/ai-in-plain-english/building-a-poker-ai-part-6-beating-kuhn-poker-with-cfr-using-python-1b4172a6ab2d
//

import Foundation

class CFRKuhn {
    
    static let actions = ["B", "C"]
    let infoSet = InformationSet()
    
    func run(numIters: Int) {
        let trainer = KuhnCFRTrainer()
        trainer.run(numIters: numIters)
    }
    
    class InformationSet {
        var cumulativeRegrets = [Float](repeating: 0, count: CFRKuhn.actions.count)
        var strategySum = [Float](repeating: 0, count: CFRKuhn.actions.count)
        var numActions = CFRKuhn.actions.count
        
        func normalize(strategy: [Float]) -> [Float] {
            var normStrategy = strategy
            let sum = normStrategy.reduce(0, +)
            
            if sum > 0 {
                normStrategy = normStrategy.map { $0  / sum }
            } else {
                let numActionsAsFloat = Float(numActions)
                normStrategy = normStrategy.map { _ in (1 / numActionsAsFloat) }
            }
            return normStrategy
        }
        
        func getStrategy(reachProbability: Float) -> [Float] {
            var strategy = cumulativeRegrets.map { max(0, $0) }
            strategy = normalize(strategy: strategy)
            
            for i in 0..<strategy.count {
                strategySum[i] += (reachProbability * strategy[i])
            }
            
            return strategy
        }
        
        func getAverageStrategy() -> [Float] {
            return normalize(strategy: strategySum)
        }
    }
    
    class KuhnPoker {
        
        static func isTerminal(history: String) -> Bool {
            return ["BC", "BB", "CC", "CBB", "CBC"].contains(history)
        }
        
        static func getPayoff(history: String, cards: [String]) -> Float {
            if ["BC", "CBC"].contains(history) {
                return 1
            } else {
                let payoff: Float = history.contains("B") ? 2 : 1
                let activePlayer = history.count % 2
                let playerCard = cards[activePlayer]
                let opponentCard = cards[(activePlayer + 1) % 2]
                if playerCard == "K" || opponentCard == "J" {
                    return payoff
                } else {
                    return -payoff
                }
            }
        }
    }
    
    class KuhnCFRTrainer {
        var infoSetMap = Dictionary<String, InformationSet>()
        
        func run(numIters: Int) {
            let util = train(numIters: numIters)
            
            let formatter = NumberFormatter()
            formatter.numberStyle = NumberFormatter.Style.decimal
            formatter.roundingMode = NumberFormatter.RoundingMode.halfUp
            formatter.maximumFractionDigits = 2
            
            print("Running Kuhn Poker chance sampling CFR for \(numIters) iterations")
            print("Expected average game value (for player 1): \((-1/18))")
            print("Computed average game value: \(util / Float(numIters))")
            print("We expect the bet frequency for a Jack to be between 0 and 1/3")
            print("The bet frequency for a King should be three times the one for a Jack")
            print("History  Bet  Pass")
            let sortedKeys = infoSetMap.keys.sorted(by: {$0.localizedStandardCompare($1) == .orderedAscending})
            for k in sortedKeys {
                let v1 = String(format: "%.2f", infoSetMap[k]!.getAverageStrategy()[0])
                let v2 = String(format: "%.2f", infoSetMap[k]!.getAverageStrategy()[1])
                print("\(k): \(v1), \(v2)")
            }
            let (expl, _) = computeExploitabilityFor(infoSetMap)
            print("Exploitability of final strategy is: \(expl)")
        }
        
        func getInfoSet(history: String) -> InformationSet {
            if infoSetMap[history] == nil {
                infoSetMap[history] = InformationSet()
            }
            return infoSetMap[history]!
        }
        
        func cfr(cards: [String], history: String, reachProbs: [Float], activePlayer: Int) -> Float {
            if KuhnPoker.isTerminal(history: history) {
                return KuhnPoker.getPayoff(history: history, cards: cards)
            }
            
            let myCard = cards[activePlayer]
            let infoSet = getInfoSet(history: myCard + history)
            
            let strategy = infoSet.getStrategy(reachProbability: reachProbs[activePlayer])
            let opponent = (activePlayer + 1) % 2
            var cfValues = [Float](repeating: 0, count: CFRKuhn.actions.count)
            
            for (ix, action) in CFRKuhn.actions.enumerated() {
                let actionProb = strategy[ix]
                
                var newReachProbs = reachProbs
                newReachProbs[activePlayer] *= actionProb
                
                let val = cfr(cards: cards, history: history + action, reachProbs: newReachProbs, activePlayer: opponent)
                cfValues[ix] = -Float(val)
            }
            
            let nodeValue = dotProduct(a: cfValues, b: strategy)
            for (ix, _) in CFRKuhn.actions.enumerated() {
                infoSet.cumulativeRegrets[ix] += (reachProbs[opponent] * (cfValues[ix] - nodeValue))
            }
            return nodeValue
        }
        
        func train(numIters: Int) -> Float {
            var util: Float = 0
            let kuhnCards = ["J", "Q", "K"]
            for _ in 0..<numIters {
                let cards = kuhnCards.sample(2)
                let history = ""
                let reachProbs = [Float](repeating: 1, count: 2)
                util += cfr(cards: cards, history: history, reachProbs: reachProbs, activePlayer: 0)
            }
            return util
        }
        
        func calcBestResponse(nodeMap: Dictionary<String, InformationSet>, brStratMap: inout Dictionary<String, [Float]>, brPlayer: Int, cards: [String], history: String, activePlayer: Int, prob: Float) -> Float {
            
            if KuhnPoker.isTerminal(history: history) {
                return -KuhnPoker.getPayoff(history: history, cards: cards)
            }
            
            let key = cards[activePlayer] + history
            let nextPlayer = (activePlayer + 1) % 2
            
            var actionVals = [Float](repeating: 0, count: actions.count)
            if activePlayer == brPlayer {
                for (ix, action) in actions.enumerated() {
                    actionVals[ix] = calcBestResponse(nodeMap: nodeMap, brStratMap: &brStratMap, brPlayer: brPlayer, cards: cards, history: history + action, activePlayer: nextPlayer, prob: prob)
                }
                let bestResponseValue = actionVals.max()!
                if brStratMap[key] == nil {
                    brStratMap[key] = [Float](repeating: 0, count: 2)
                }
                brStratMap[key] = brStratMap[key]! + actionVals.map { $0 * prob }
                return -bestResponseValue
            } else {
                let strategy = nodeMap[key]!.getAverageStrategy()
                for (ix, action) in actions.enumerated() {
                    actionVals[ix] = calcBestResponse(nodeMap: nodeMap, brStratMap: &brStratMap, brPlayer: brPlayer, cards: cards, history: history + action, activePlayer: nextPlayer, prob: prob * strategy[ix])
                }
                return dotProduct(a: strategy, b: actionVals)
            }
        }
        
        func calcEV(p1Strat: Dictionary<String, [Float]>, p2Strat: Dictionary<String, [Float]>, cards: [String], history: String, activePlayer: Int) -> Float {
            
            if KuhnPoker.isTerminal(history: history) {
                return -KuhnPoker.getPayoff(history: history, cards: cards)
            }
            
            let myCard = cards[activePlayer]
            let nextPlayer = (activePlayer + 1) % 2
            
            var strat: [Float]
            if activePlayer == 0 {
                strat = p1Strat[myCard + history]!
            } else {
                strat = p2Strat[myCard + history]!
            }
            
            var actionVals = [Float](repeating: 0, count: actions.count)
            for (ix, action) in actions.enumerated() {
                actionVals[ix] = calcEV(p1Strat: p1Strat, p2Strat: p2Strat, cards: cards, history: history + action, activePlayer: nextPlayer)
            }
            return -dotProduct(a: strat, b: actionVals)
        }
        
        func computeExploitabilityFor(_ infoSetMap: Dictionary<String, InformationSet>) -> (Float, Dictionary<String, [Float]>) {
            let kuhnCards = ["J", "Q", "K"]
            var exploitability: Float = 0
            var brStratMap = Dictionary<String, [Float]>()
            
            for cards in kuhnCards.permutations {
                let _ = calcBestResponse(nodeMap: infoSetMap, brStratMap: &brStratMap, brPlayer: 0, cards: cards, history: "", activePlayer: 0, prob: 1)
                let _ = calcBestResponse(nodeMap: infoSetMap, brStratMap: &brStratMap, brPlayer: 1, cards: cards, history: "", activePlayer: 0, prob: 1)
            }
            
            for (k,v) in brStratMap {
                brStratMap[k] = v.map { $0 == v.max() ? 1 : 0 }
            }
            var cfrStrategy = Dictionary<String, [Float]>()
            for (k,v) in infoSetMap {
                cfrStrategy[k] = v.getAverageStrategy()
            }
            for cards in kuhnCards.permutations {
                let ev1 = calcEV(p1Strat: cfrStrategy, p2Strat: brStratMap, cards: cards, history: "", activePlayer: 0)
                let ev2 = calcEV(p1Strat: brStratMap, p2Strat: cfrStrategy, cards: cards, history: "", activePlayer: 0)
                exploitability += Float(1 / 6) * (ev1 - ev2)
            }
            return (exploitability, brStratMap)
        }
        
        private func dotProduct(a: [Float], b: [Float]) -> Float {
            return zip(a, b).map(*).reduce(0, +)
        }
        
        
        private func multiply(a: [Float], b: [Float]) -> [Float] {
            return zip(a, b).map(*)
        }
    }
        
}
