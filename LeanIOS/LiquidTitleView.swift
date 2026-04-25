//
//  LiquidTitleView.swift
//  MedianIOS
//
//  Created by Hunaid Hassan on 14.01.26.
//  Copyright © 2026 GoNative.io LLC. All rights reserved.
//


import UIKit

@available(iOS 26.0, *)
@objc(LEANLiquidTitleView)
class LiquidTitleView: UIView {
    
    private let label = UILabel()
    private let glassView: UIVisualEffectView = {
        // Use UIGlassEffect for the iOS 26 "Liquid" look
        let effect = UIGlassEffect()
        return UIVisualEffectView(effect: effect)
    }()
    
    @objc
    var text: String? {
        didSet {
            label.text = text
            // 1. Tell the system our size has changed
            self.invalidateIntrinsicContentSize()
            // 2. Animate the frame change for the "liquid" feel
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
                self.superview?.setNeedsLayout()
                self.superview?.layoutIfNeeded()
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        // Configure Glass
        glassView.layer.cornerRadius = 22 // Adjust for bubble roundness
        glassView.clipsToBounds = true
        addSubview(glassView)
        
        // Configure Label
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        addSubview(label)
        
        // Setup Constraints
        label.translatesAutoresizingMaskIntoConstraints = false
        glassView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Label is inset from the bubble edges
            label.topAnchor.constraint(equalTo: self.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            
            // Glass view fills the entire container
            glassView.topAnchor.constraint(equalTo: self.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            glassView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
    }
    
    // 3. This is the fix for the zero-frame/no-resize issue
    override var intrinsicContentSize: CGSize {
        let labelSize = label.intrinsicContentSize
        // Return the label size + padding
        return CGSize(width: labelSize.width + 32, height: 44)
    }
}
