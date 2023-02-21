// SPDX-License-Identifier: GPL-3.0

/// @title The Smol Joe art storage contract
/// Inspired by Nouns DAO's NounsArt contract

pragma solidity ^0.8.6;

import {ISmolJoeArt} from "./interfaces/ISmolJoeArt.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {IInflator} from "./interfaces/IInflator.sol";

contract SmolJoeArt is ISmolJoeArt {
    /// @notice Current Smol Joe Descriptor address
    address public override descriptor;

    /// @notice Current inflator address
    IInflator public override inflator;

    /// @notice Smol Joe Backgrounds (Hex Colors)
    string[] public override backgrounds;

    /// @notice Smol Joe Color Palettes (Index => Hex Colors, stored as a contract using SSTORE2)
    mapping(uint8 => address) public palettesPointers;

    /// @notice Smol Joe Bodies Trait
    Trait public bodiesTrait;

    /// @notice Smol Joe Heads Trait
    Trait public headsTrait;

    /**
     * @notice Require that the sender is the descriptor.
     */
    modifier onlyDescriptor() {
        if (msg.sender != descriptor) {
            revert SenderIsNotDescriptor();
        }
        _;
    }

    constructor(address _descriptor, IInflator _inflator) {
        descriptor = _descriptor;
        inflator = _inflator;
    }

    /**
     * @notice Set the descriptor.
     * @dev This function can only be called by the current descriptor.
     */
    function setDescriptor(address _descriptor) external override onlyDescriptor {
        address oldDescriptor = descriptor;
        descriptor = _descriptor;

        emit DescriptorUpdated(oldDescriptor, descriptor);
    }

    /**
     * @notice Set the inflator.
     * @dev This function can only be called by the descriptor.
     */
    function setInflator(IInflator _inflator) external override onlyDescriptor {
        address oldInflator = address(inflator);
        inflator = _inflator;

        emit InflatorUpdated(oldInflator, address(_inflator));
    }

    /**
     * @notice Get the Trait struct for bodies.
     * @dev This explicit getter is needed because implicit getters for structs aren't fully supported yet:
     * https://github.com/ethereum/solidity/issues/11826
     * @return Trait the struct, including a total image count, and an array of storage pages.
     */
    function getBodiesTrait() external view override returns (Trait memory) {
        return bodiesTrait;
    }

    /**
     * @notice Get the Trait struct for heads.
     * @dev This explicit getter is needed because implicit getters for structs aren't fully supported yet:
     * https://github.com/ethereum/solidity/issues/11826
     * @return Trait the struct, including a total image count, and an array of storage pages.
     */
    function getHeadsTrait() external view override returns (Trait memory) {
        return headsTrait;
    }

    /**
     * @notice Batch add Smol Joe backgrounds.
     * @dev This function can only be called by the descriptor.
     */
    function addManyBackgrounds(string[] calldata _backgrounds) external override onlyDescriptor {
        for (uint256 i = 0; i < _backgrounds.length; i++) {
            _addBackground(_backgrounds[i]);
        }

        emit BackgroundsAdded(_backgrounds.length);
    }

    /**
     * @notice Add a Smol Joe background.
     * @dev This function can only be called by the descriptor.
     */
    function addBackground(string calldata _background) external override onlyDescriptor {
        _addBackground(_background);

        emit BackgroundsAdded(1);
    }

    /**
     * @notice Update a single color palette. This function can be used to
     * add a new color palette or update an existing palette.
     * @param paletteIndex the identifier of this palette
     * @param palette byte array of colors. every 3 bytes represent an RGB color. max length: 256 * 3 = 768
     * @dev This function can only be called by the descriptor.
     */
    function setPalette(uint8 paletteIndex, bytes calldata palette) external override onlyDescriptor {
        if (palette.length == 0) {
            revert EmptyPalette();
        }
        if (palette.length % 3 != 0 || palette.length > 768) {
            revert BadPaletteLength();
        }
        palettesPointers[paletteIndex] = SSTORE2.write(palette);

        emit PaletteSet(paletteIndex);
    }

    /**
     * @notice Add a batch of body images.
     * @param encodedCompressed bytes created by taking a string array of RLE-encoded images, abi encoding it as a bytes array,
     * and finally compressing it using deflate.
     * @param decompressedLength the size in bytes the images bytes were prior to compression; required input for Inflate.
     * @param imageCount the number of images in this batch; used when searching for images among batches.
     * @dev This function can only be called by the descriptor.
     */
    function addBodies(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
        external
        override
        onlyDescriptor
    {
        addPage(bodiesTrait, encodedCompressed, decompressedLength, imageCount);

        emit BodiesAdded(imageCount);
    }

    /**
     * @notice Add a batch of head images.
     * @param encodedCompressed bytes created by taking a string array of RLE-encoded images, abi encoding it as a bytes array,
     * and finally compressing it using deflate.
     * @param decompressedLength the size in bytes the images bytes were prior to compression; required input for Inflate.
     * @param imageCount the number of images in this batch; used when searching for images among batches.
     * @dev This function can only be called by the descriptor.
     */
    function addHeads(bytes calldata encodedCompressed, uint80 decompressedLength, uint16 imageCount)
        external
        override
        onlyDescriptor
    {
        addPage(headsTrait, encodedCompressed, decompressedLength, imageCount);

        emit HeadsAdded(imageCount);
    }

    /**
     * @notice Update a single color palette. This function can be used to
     * add a new color palette or update an existing palette. This function does not check for data length validity
     * (len <= 768, len % 3 == 0).
     * @param paletteIndex the identifier of this palette
     * @param pointer the address of the contract holding the palette bytes. every 3 bytes represent an RGB color.
     * max length: 256 * 3 = 768.
     * @dev This function can only be called by the descriptor.
     */
    function setPalettePointer(uint8 paletteIndex, address pointer) external override onlyDescriptor {
        palettesPointers[paletteIndex] = pointer;

        emit PaletteSet(paletteIndex);
    }

    /**
     * @notice Add a batch of body images from an existing storage contract.
     * @param pointer the address of a contract where the image batch was stored using SSTORE2. The data
     * format is expected to be like {encodedCompressed}: bytes created by taking a string array of
     * RLE-encoded images, abi encoding it as a bytes array, and finally compressing it using deflate.
     * @param decompressedLength the size in bytes the images bytes were prior to compression; required input for Inflate.
     * @param imageCount the number of images in this batch; used when searching for images among batches.
     * @dev This function can only be called by the descriptor.
     */
    function addBodiesFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
        external
        override
        onlyDescriptor
    {
        addPage(bodiesTrait, pointer, decompressedLength, imageCount);

        emit BodiesAdded(imageCount);
    }

    /**
     * @notice Add a batch of head images from an existing storage contract.
     * @param pointer the address of a contract where the image batch was stored using SSTORE2. The data
     * format is expected to be like {encodedCompressed}: bytes created by taking a string array of
     * RLE-encoded images, abi encoding it as a bytes array, and finally compressing it using deflate.
     * @param decompressedLength the size in bytes the images bytes were prior to compression; required input for Inflate.
     * @param imageCount the number of images in this batch; used when searching for images among batches
     * @dev This function can only be called by the descriptor..
     */
    function addHeadsFromPointer(address pointer, uint80 decompressedLength, uint16 imageCount)
        external
        override
        onlyDescriptor
    {
        addPage(headsTrait, pointer, decompressedLength, imageCount);

        emit HeadsAdded(imageCount);
    }

    /**
     * @notice Get the number of available Smol Joe `backgrounds`.
     */
    function backgroundsCount() public view override returns (uint256) {
        return backgrounds.length;
    }

    /**
     * @notice Get a head image bytes (RLE-encoded).
     */
    function heads(uint256 index) public view override returns (bytes memory) {
        return imageByIndex(headsTrait, index);
    }

    /**
     * @notice Get a body image bytes (RLE-encoded).
     */
    function bodies(uint256 index) public view override returns (bytes memory) {
        return imageByIndex(bodiesTrait, index);
    }

    /**
     * @notice Get a color palette bytes.
     */
    function palettes(uint8 paletteIndex) public view override returns (bytes memory) {
        address pointer = palettesPointers[paletteIndex];
        if (pointer == address(0)) {
            revert PaletteNotFound();
        }
        return SSTORE2.read(palettesPointers[paletteIndex]);
    }

    function _addBackground(string calldata _background) internal {
        backgrounds.push(_background);
    }

    function addPage(
        Trait storage trait,
        bytes calldata encodedCompressed,
        uint80 decompressedLength,
        uint16 imageCount
    ) internal {
        if (encodedCompressed.length == 0) {
            revert EmptyBytes();
        }
        address pointer = SSTORE2.write(encodedCompressed);
        addPage(trait, pointer, decompressedLength, imageCount);
    }

    function addPage(Trait storage trait, address pointer, uint80 decompressedLength, uint16 imageCount) internal {
        if (decompressedLength == 0) {
            revert BadDecompressedLength();
        }
        if (imageCount == 0) {
            revert BadImageCount();
        }
        trait.storagePages.push(
            SmolJoeArtStoragePage({pointer: pointer, decompressedLength: decompressedLength, imageCount: imageCount})
        );
        trait.storedImagesCount += imageCount;
    }

    function imageByIndex(ISmolJoeArt.Trait storage trait, uint256 index) internal view returns (bytes memory) {
        (ISmolJoeArt.SmolJoeArtStoragePage storage page, uint256 indexInPage) = getPage(trait.storagePages, index);
        bytes[] memory decompressedImages = decompressAndDecode(page);
        return decompressedImages[indexInPage];
    }

    /**
     * @dev Given an image index, this function finds the storage page the image is in, and the relative index
     * inside the page, so the image can be read from storage.
     * Example: if you have 2 pages with 100 images each, and you want to get image 150, this function would return
     * the 2nd page, and the 50th index.
     * @return ISmolJoeArt.SmolJoeArtStoragePage the page containing the image at index
     * @return uint256 the index of the image in the page
     */
    function getPage(ISmolJoeArt.SmolJoeArtStoragePage[] storage pages, uint256 index)
        internal
        view
        returns (ISmolJoeArt.SmolJoeArtStoragePage storage, uint256)
    {
        uint256 len = pages.length;
        uint256 pageFirstImageIndex = 0;
        for (uint256 i = 0; i < len; i++) {
            ISmolJoeArt.SmolJoeArtStoragePage storage page = pages[i];

            if (index < pageFirstImageIndex + page.imageCount) {
                return (page, index - pageFirstImageIndex);
            }

            pageFirstImageIndex += page.imageCount;
        }

        revert ImageNotFound();
    }

    function decompressAndDecode(ISmolJoeArt.SmolJoeArtStoragePage storage page)
        internal
        view
        returns (bytes[] memory)
    {
        bytes memory compressedData = SSTORE2.read(page.pointer);
        (, bytes memory decompressedData) = inflator.puff(compressedData, page.decompressedLength);
        return abi.decode(decompressedData, (bytes[]));
    }
}
