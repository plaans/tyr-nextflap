#!/bin/bash
set -e

# NextFLAP Installation Script
# This script builds and installs NextFLAP for the current Python environment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="/tmp/nextflap_build_$$"
PYTHON_CMD=${PYTHON_CMD:-python}

echo "🚀 NextFLAP Installation Starting..."
echo "Using Python: $(which $PYTHON_CMD) ($(${PYTHON_CMD} --version))"

# Function to cleanup on exit
cleanup() {
    echo "🧹 Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

# Check if we're in a virtual environment
if [[ -z "${VIRTUAL_ENV}" && -z "${CONDA_DEFAULT_ENV}" ]]; then
    echo "⚠️  Warning: Not in a virtual environment. Consider activating one first."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check Python version
PYTHON_VERSION=$(${PYTHON_CMD} -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "📋 Python version: $PYTHON_VERSION"

# Install Python dependencies
echo "📦 Installing Python dependencies..."
${PYTHON_CMD} -m pip install pybind11 numpy unified-planning

# Check for system dependencies
echo "🔍 Checking system dependencies..."

# Check for g++
if ! command -v g++ &> /dev/null; then
    echo "❌ g++ not found. Please install build-essential or equivalent."
    echo "   Ubuntu/Debian: sudo apt install build-essential"
    echo "   CentOS/RHEL: sudo yum install gcc-c++"
    exit 1
fi

# Check for Z3
if ! pkg-config --exists z3; then
    echo "❌ Z3 development libraries not found."
    echo "   Ubuntu/Debian: sudo apt install libz3-dev"
    echo "   CentOS/RHEL: sudo yum install z3-devel"
    exit 1
fi

Z3_PREFIX=$(pkg-config --variable=prefix z3)
echo "✅ Found Z3 at: $Z3_PREFIX"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Copy local source to build directory
echo "📥 Copying local NextFLAP source..."
LOCAL_SOURCE_DIR="/home/roland/tyr/src/tyr/planners/planners/nextflap/src"
if [[ ! -d "$LOCAL_SOURCE_DIR" ]]; then
    echo "❌ Local source directory not found: $LOCAL_SOURCE_DIR"
    exit 1
fi
cp -r "$LOCAL_SOURCE_DIR"/* "$BUILD_DIR/"
echo "✅ Local source copied successfully"

# Clean any previous build artifacts
echo "🔧 Cleaning previous build artifacts..."
cd nextflap
rm -f *.o *.so 2>/dev/null || true
echo "✅ Build artifacts cleaned"

# Check if patches are already applied and apply if needed
echo "🔧 Checking and applying compatibility patches if needed..."

# Check if pybind11 include is already fixed
if grep -q '#include <pybind11\.h>' nextflap.cpp; then
    echo "📝 Fixing pybind11 include in nextflap.cpp..."
    sed -i 's/#include <pybind11\.h>/#include <pybind11\/pybind11.h>/' nextflap.cpp
else
    echo "✅ pybind11 include already fixed in nextflap.cpp"
fi

# Check if getPybindFolder function needs fixing
if grep -A5 'def getPybindFolder():' setup.py | grep -q 'path.append.*pybind11'; then
    echo "✅ getPybindFolder function already fixed in setup.py"
else
    echo "📝 Fixing getPybindFolder function in setup.py..."
    cat > setup_patch.py << 'EOF'
def getPybindFolder():
    try:
        import pybind11
    except:
        raise Exception('pybind11 module not found.\nTry installing it using the following command: pip install pybind11')
    path = pybind11.__file__.split(os.sep)[:-1]
    path.append('include')
    folder = path[0] + os.sep
    for i in range(1, len(path)):
        folder = os.path.join(folder, path[i])
    header = os.path.join(folder, 'pybind11', 'pybind11.h')
    if not os.path.exists(header):
        error(f'check the pybind11 installation. File {header} not found.')
    print('* pybind11 module found in', folder)
    return folder
EOF

    # Replace the getPybindFolder function using sed
    sed -i '/def getPybindFolder():/,/return folder/c\
# PLACEHOLDER_FOR_FUNCTION' setup.py

    # Now replace the placeholder with our patched function
    sed -i '/# PLACEHOLDER_FOR_FUNCTION/r setup_patch.py' setup.py
    sed -i '/# PLACEHOLDER_FOR_FUNCTION/d' setup.py
    rm setup_patch.py
fi

# Check if up_nextflap.py is already in nextflap directory (our local version should have it)
if [[ ! -f "up_nextflap.py" ]]; then
    echo "📝 Copying up_nextflap.py to nextflap directory..."
    if [[ -f "../up_nextflap/up_nextflap.py" ]]; then
        cp ../up_nextflap/up_nextflap.py .
    else
        echo "❌ up_nextflap.py not found in expected location"
        exit 1
    fi
else
    echo "✅ up_nextflap.py already present in nextflap directory"
fi

# Build NextFLAP
echo "🔨 Building NextFLAP..."
# We're already in the build directory with nextflap source

# Run setup script with Z3 path
# Setup.py expects Z3 prefix and will look for lib/libz3.so
# Create a temporary structure if needed
if [[ ! -f "$Z3_PREFIX/lib/libz3.so" ]]; then
    Z3_LIBDIR=$(pkg-config --variable=libdir z3)
    mkdir -p temp_z3/lib temp_z3/include
    ln -sf "$Z3_LIBDIR"/libz3.so* temp_z3/lib/
    cp /usr/include/z3*.h temp_z3/include/ 2>/dev/null || true
    echo "$(pwd)/temp_z3" | ${PYTHON_CMD} setup.py
    rm -rf temp_z3
else
    echo "$Z3_PREFIX" | ${PYTHON_CMD} setup.py
fi

# Check if build succeeded
if [[ ! -f "nextflap.so" ]]; then
    echo "❌ Build failed: nextflap.so not found"
    exit 1
fi

echo "✅ Build successful: nextflap.so created"

# Install to Python environment
echo "📤 Installing NextFLAP to Python environment..."

# Uninstall any existing up-nextflap package to avoid conflicts
echo "📦 Removing any existing up-nextflap package..."
${PYTHON_CMD} -m pip uninstall -y up-nextflap 2>/dev/null || true

# Create our own up_nextflap package structure
echo "📦 Creating custom up_nextflap package structure..."
SITE_PACKAGES=$(${PYTHON_CMD} -c "import site; print(site.getsitepackages()[0])")
UP_NEXTFLAP_PATH="$SITE_PACKAGES/up_nextflap"
mkdir -p "$UP_NEXTFLAP_PATH"

# Copy Python files to create the package
cp ../up_nextflap/__init__.py "$UP_NEXTFLAP_PATH/"
cp ../up_nextflap/up_nextflap.py "$UP_NEXTFLAP_PATH/"

echo "📁 up_nextflap package location: $UP_NEXTFLAP_PATH"

# Copy the built module
cp nextflap.so "$UP_NEXTFLAP_PATH/"
echo "✅ Copied nextflap.so to package directory"

# Verify installation
echo "🧪 Verifying installation..."
if ${PYTHON_CMD} -c "from up_nextflap import NextFLAPImpl; print('✅ NextFLAP import successful')" 2>/dev/null; then
    echo "🎉 NextFLAP installation completed successfully!"
else
    echo "❌ Installation verification failed"
    exit 1
fi